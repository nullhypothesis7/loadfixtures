package com.testfixtures.controller;

import com.testfixtures.config.AppConfig;
import com.testfixtures.inspector.DdlInspector;
import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.model.Run;
import com.testfixtures.queue.RedisQueue;
import com.testfixtures.repository.RunRepository;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/ddl")
public class DdlController {

    // Postgres SQLSTATE for "duplicate_table" — thrown by a plain CREATE TABLE
    // (no IF NOT EXISTS) when the relation is already there. Re-POSTing the
    // same DDL against a database that's already been set up is a normal
    // workflow (e.g. re-running this test), not an error.
    private static final String DUPLICATE_TABLE_SQLSTATE = "42P07";

    private final AppConfig     appConfig;
    private final RunRepository runRepository;
    private final RedisQueue    redisQueue;
    private final RunMetrics    runMetrics;

    public DdlController(AppConfig appConfig, RunRepository runRepository, RedisQueue redisQueue,
                         RunMetrics runMetrics) {
        this.appConfig     = appConfig;
        this.runRepository = runRepository;
        this.redisQueue    = redisQueue;
        this.runMetrics    = runMetrics;
    }

    record DdlRequest(String targetDatabase, String ddl, String targetType) {}

    @PostMapping("/inspect")
    public ResponseEntity<List<PipeDefinition>> inspect(@RequestBody DdlRequest request) {
        List<PipeDefinition> pipes = parsePipes(request);
        return ResponseEntity.ok(pipes);
    }

    @PostMapping("/load")
    public ResponseEntity<List<Run>> load(@RequestBody DdlRequest request) {
        List<PipeDefinition> pipes = parsePipes(request);
        executeDdl(request.targetDatabase().toLowerCase(), request.ddl());

        List<Run> runs = new ArrayList<>(pipes.size());
        for (PipeDefinition pipe : pipes) {
            String runId = UUID.randomUUID().toString();
            Run run = new Run(runId, pipe.getPipeName(), "QUEUED", Instant.now());
            runRepository.save(run);
            runMetrics.increment("QUEUED");
            pipe.setRunId(runId);
            try {
                redisQueue.enqueue(pipe);
            } catch (Exception e) {
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                        "Failed to enqueue pipe '" + pipe.getPipeName() + "': " + e.getMessage(), e);
            }
            runs.add(run);
        }
        return ResponseEntity.ok(runs);
    }

    // Actually runs the caller's CREATE TABLE statements against the target
    // database. parsePipes() only reads the DDL text to infer column types —
    // nothing before this point ever creates the tables, so without this the
    // pipes queued below hit "relation does not exist" on their first insert.
    private void executeDdl(String targetDatabase, String ddl) {
        String jdbcUrl = appConfig.getDatabaseUrls().get(targetDatabase);
        if (jdbcUrl == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "No database configured for '" + targetDatabase
                            + "' — check DB_URL_" + targetDatabase.toUpperCase() + " env var");
        }

        HikariConfig hc = new HikariConfig();
        hc.setJdbcUrl(jdbcUrl);
        hc.setUsername(appConfig.getDatabaseUsers().getOrDefault(targetDatabase, appConfig.getUsername()));
        hc.setPassword(appConfig.getDatabasePasswords().getOrDefault(targetDatabase, appConfig.getPassword()));
        hc.setMaximumPoolSize(1);
        hc.setConnectionTimeout(5_000);

        try (HikariDataSource ds = new HikariDataSource(hc);
             java.sql.Connection conn = ds.getConnection();
             Statement stmt = conn.createStatement()) {
            stmt.execute(ddl);
        } catch (SQLException e) {
            if (DUPLICATE_TABLE_SQLSTATE.equals(e.getSQLState())) {
                System.out.printf("DDL for '%s' already applied (table exists) — continuing%n", targetDatabase);
                return;
            }
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Failed to execute DDL against '" + targetDatabase + "': " + e.getMessage(), e);
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Failed to execute DDL against '" + targetDatabase + "': " + e.getMessage(), e);
        }
    }

    private List<PipeDefinition> parsePipes(DdlRequest request) {
        if (request.targetDatabase() == null || request.targetDatabase().isBlank())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "targetDatabase is required");
        if (request.ddl() == null || request.ddl().isBlank())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "ddl is required");

        try {
            List<PipeDefinition> pipes = new DdlInspector()
                    .inspect(request.targetDatabase().toLowerCase(), request.ddl());
            if (pipes.isEmpty())
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "No CREATE TABLE statements found in provided DDL");
            if (request.targetType() != null && !request.targetType().isBlank()) {
                String type = request.targetType().toUpperCase();
                if (!"JDBC".equals(type)) pipes.forEach(p -> p.setTargetType(type));
            }
            return pipes;
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "DDL parse error: " + e.getMessage(), e);
        }
    }
}
