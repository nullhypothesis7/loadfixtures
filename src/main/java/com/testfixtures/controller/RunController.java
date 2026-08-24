package com.testfixtures.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.model.Run;
import com.testfixtures.queue.RedisQueue;
import com.testfixtures.repository.RunRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.util.UUID;

@RestController
@RequestMapping("/api/runs")
public class RunController {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RunRepository runRepository;
    private final RedisQueue redisQueue;
    private final RunMetrics runMetrics;

    public RunController(RunRepository runRepository, RedisQueue redisQueue, RunMetrics runMetrics) {
        this.runRepository = runRepository;
        this.redisQueue = redisQueue;
        this.runMetrics = runMetrics;
    }

    record CreateRunRequest(String pipeName) {}

    @PostMapping
    public ResponseEntity<Run> createRun(@RequestBody CreateRunRequest request) {
        PipeDefinition pipe = loadPipe(request.pipeName());

        Run run = new Run(UUID.randomUUID().toString(), request.pipeName(), "QUEUED", Instant.now());
        runRepository.save(run);
        runMetrics.increment("QUEUED");
        pipe.setRunId(run.getId());

        try {
            redisQueue.enqueue(pipe);
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Failed to enqueue run", e);
        }

        return ResponseEntity.ok(run);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Run> getRun(@PathVariable("id") String id) {
        return runRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    private PipeDefinition loadPipe(String pipeName) {
        String path = "/pipes/" + pipeName + ".json";
        try (InputStream is = getClass().getResourceAsStream(path)) {
            if (is == null) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Unknown pipe: " + pipeName);
            }
            return MAPPER.readValue(is, PipeDefinition.class);
        } catch (IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Failed to load pipe: " + pipeName);
        }
    }
}
