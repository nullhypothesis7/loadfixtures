package com.testfixtures.controller;

import com.testfixtures.config.AppConfig;
import com.testfixtures.inspector.SchemaInspector;
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

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.Collections;

@RestController
@RequestMapping("/api/schema")
public class SchemaController {

    private final AppConfig appConfig;
    private final RunRepository runRepository;
    private final RedisQueue redisQueue;
    private final RunMetrics runMetrics;

    public SchemaController(AppConfig appConfig, RunRepository runRepository,
                            RedisQueue redisQueue, RunMetrics runMetrics) {
        this.appConfig    = appConfig;
        this.runRepository = runRepository;
        this.redisQueue   = redisQueue;
        this.runMetrics   = runMetrics;
    }

    record SchemaRequest(String targetDatabase, String targetType, List<String> schemas) {}

    @PostMapping("/inspect")
    public ResponseEntity<List<PipeDefinition>> inspect(@RequestBody SchemaRequest request) {
        List<PipeDefinition> pipes = inspectPipes(request.targetDatabase(), request.schemas());
        applyTargetType(pipes, request.targetType());
        return ResponseEntity.ok(pipes);
    }

    @PostMapping("/load")
    public ResponseEntity<List<Run>> load(@RequestBody SchemaRequest request) {
        List<PipeDefinition> pipes = inspectPipes(request.targetDatabase(), request.schemas());
        applyTargetType(pipes, request.targetType());

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

    private static void applyTargetType(List<PipeDefinition> pipes, String targetType) {
        if (targetType == null || targetType.isBlank()) return;
        String resolved = targetType.toUpperCase();
        if ("JDBC".equals(resolved)) return;
        pipes.forEach(p -> p.setTargetType(resolved));
    }

    // ── shared ────────────────────────────────────────────────────────────────

    private List<PipeDefinition> inspectPipes(String targetDatabase, List<String> schemas) {
        if (targetDatabase == null || targetDatabase.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "targetDatabase is required");
        }

        String key = targetDatabase.toLowerCase();
        String jdbcUrl = appConfig.getDatabaseUrls().get(key);
        if (jdbcUrl == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "No database configured for '" + targetDatabase
                            + "' — check DB_URL_" + targetDatabase.toUpperCase() + " env var");
        }

        List<String> effectiveSchemas = (schemas == null || schemas.isEmpty())
                ? Collections.singletonList("public") : schemas;

        HikariConfig hc = new HikariConfig();
        hc.setJdbcUrl(jdbcUrl);
        hc.setUsername(appConfig.getDatabaseUsers().getOrDefault(key, appConfig.getUsername()));
        hc.setPassword(appConfig.getDatabasePasswords().getOrDefault(key, appConfig.getPassword()));
        hc.setMaximumPoolSize(2);
        hc.setConnectionTimeout(5_000);

        try (HikariDataSource ds = new HikariDataSource(hc)) {
            return new SchemaInspector(ds).inspect(key, effectiveSchemas);
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Schema inspection failed: " + e.getMessage(), e);
        }
    }
}
