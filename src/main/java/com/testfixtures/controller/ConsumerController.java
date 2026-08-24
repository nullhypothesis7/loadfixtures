package com.testfixtures.controller;

import com.testfixtures.config.AppConfig;
import com.testfixtures.consumer.KafkaConsumerService;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Collections;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/consumer")
public class ConsumerController {

    private final AppConfig appConfig;

    public ConsumerController(AppConfig appConfig) {
        this.appConfig = appConfig;
    }

    record ConsumeRequest(String targetDatabase, List<String> schemas) {}

    @PostMapping("/run")
    public ResponseEntity<Map<String, Object>> run(@RequestBody ConsumeRequest request) {
        if (request.targetDatabase() == null || request.targetDatabase().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "targetDatabase is required");
        }

        String key = request.targetDatabase().toLowerCase();
        String jdbcUrl = appConfig.getDatabaseUrls().get(key);
        if (jdbcUrl == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "No database configured for '" + request.targetDatabase()
                            + "' — check DB_URL_" + request.targetDatabase().toUpperCase() + " env var");
        }

        List<String> schemas = (request.schemas() == null || request.schemas().isEmpty())
                ? Collections.singletonList("public") : request.schemas();

        HikariConfig hc = new HikariConfig();
        hc.setJdbcUrl(jdbcUrl);
        hc.setUsername(appConfig.getDatabaseUsers().getOrDefault(key, appConfig.getUsername()));
        hc.setPassword(appConfig.getDatabasePasswords().getOrDefault(key, appConfig.getPassword()));
        hc.setMaximumPoolSize(4);

        try (HikariDataSource ds = new HikariDataSource(hc)) {
            KafkaConsumerService service = new KafkaConsumerService(
                    appConfig.getKafkaBootstrapServers(),
                    appConfig.getSchemaRegistryUrl());
            KafkaConsumerService.ConsumeResult result = service.consume(key, schemas, ds);
            return ResponseEntity.ok(Map.of(
                    "status",         "complete",
                    "tablesConsumed", result.tablesConsumed(),
                    "rowsWritten",    result.rowsWritten()));
        } catch (ResponseStatusException e) {
            throw e;
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "Consumer failed: " + e.getMessage(), e);
        }
    }
}
