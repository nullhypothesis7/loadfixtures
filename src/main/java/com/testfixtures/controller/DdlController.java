package com.testfixtures.controller;

import com.testfixtures.inspector.DdlInspector;
import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.model.Run;
import com.testfixtures.queue.RedisQueue;
import com.testfixtures.repository.RunRepository;
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

@RestController
@RequestMapping("/api/ddl")
public class DdlController {

    private final RunRepository runRepository;
    private final RedisQueue    redisQueue;
    private final RunMetrics    runMetrics;

    public DdlController(RunRepository runRepository, RedisQueue redisQueue,
                         RunMetrics runMetrics) {
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
