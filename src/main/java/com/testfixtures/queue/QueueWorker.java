package com.testfixtures.queue;

import com.testfixtures.config.AppConfig;
import com.testfixtures.loader.RowGenerator;
import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.repository.RunRepository;
import com.testfixtures.sink.CsvSink;
import com.testfixtures.sink.DataSink;
import com.testfixtures.sink.JdbcSink;
import com.testfixtures.sink.KafkaSink;
import com.testfixtures.sink.ParquetSink;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import java.util.Optional;

public class QueueWorker implements Runnable {

    private final RedisQueue queue;
    private final AppConfig config;
    private final RunRepository runRepository;
    private final RunMetrics runMetrics;
    private volatile boolean running = true;

    public QueueWorker(RedisQueue queue, AppConfig config, RunRepository runRepository, RunMetrics runMetrics) {
        this.queue = queue;
        this.config = config;
        this.runRepository = runRepository;
        this.runMetrics = runMetrics;
    }

    public void stop() {
        running = false;
    }

    @Override
    public void run() {
        java.util.Set<String> domains = new java.util.LinkedHashSet<>(config.getDatabaseUrls().keySet());
        domains.add(RedisQueue.CSV_DOMAIN);
        domains.add(RedisQueue.PARQUET_DOMAIN);
        domains.add(RedisQueue.KAFKA_DOMAIN);
        System.out.printf("Worker started, listening on queues: %s%n",
                domains.stream().map(RedisQueue::queueKey).toList());

        while (running) {
            try {
                Optional<PipeDefinition> maybePipe = queue.dequeue(5, domains);
                if (maybePipe.isEmpty()) {
                    continue;
                }
                PipeDefinition pipe = maybePipe.get();
                System.out.printf("Worker picked up pipe: %s%n", pipe.getPipeName());

                String targetType = pipe.getTargetType() != null ? pipe.getTargetType().toUpperCase() : "JDBC";

                HikariDataSource ds = null;
                DataSink sink;
                if ("JDBC".equals(targetType)) {
                    String targetDb = pipe.getTargetDatabase();
                    if (targetDb == null || targetDb.isBlank()) {
                        System.err.printf("Pipe '%s' has no targetDatabase set — marking FAILED%n", pipe.getPipeName());
                        updateStatus(pipe.getRunId(), "FAILED");
                        continue;
                    }
                    String jdbcUrl = config.getDatabaseUrls().get(targetDb);
                    if (jdbcUrl == null) {
                        System.err.printf("No JDBC URL configured for database '%s' — marking FAILED%n", targetDb);
                        updateStatus(pipe.getRunId(), "FAILED");
                        continue;
                    }
                    HikariConfig hc = new HikariConfig();
                    hc.setJdbcUrl(jdbcUrl);
                    hc.setUsername(config.getDatabaseUsers().getOrDefault(targetDb, config.getUsername()));
                    hc.setPassword(config.getDatabasePasswords().getOrDefault(targetDb, config.getPassword()));
                    hc.setMaximumPoolSize(pipe.getConcurrency() + 1);
                    ds = new HikariDataSource(hc);
                    sink = new JdbcSink(ds);

                    resolveFkRanges(pipe);
                } else if ("CSV".equals(targetType)) {
                    sink = new CsvSink(config.getCsvOutputDir());
                } else if ("KAFKA".equals(targetType)) {
                    sink = new KafkaSink(config.getKafkaBootstrapServers(), config.getSchemaRegistryUrl());
                } else if ("PARQUET".equals(targetType)) {
                    sink = new ParquetSink(config.getParquetOutputDir());
                } else {
                    System.err.printf("Unsupported targetType '%s' for pipe '%s' — marking FAILED%n",
                            pipe.getTargetType(), pipe.getPipeName());
                    updateStatus(pipe.getRunId(), "FAILED");
                    continue;
                }

                updateStatus(pipe.getRunId(), "RUNNING");
                if ("JDBC".equals(targetType) && pipe.getPkColumn() != null) {
                    pipe.setSequenceOffset(queue.reserveSequenceRange(
                            pipe.getTargetDatabase(), pipe.getTargetTable(), pipe.getTotalRows()));
                }
                java.util.List<java.util.Map<String, Object>> rows = RowGenerator.generate(pipe);
                try {
                    sink.write(rows, pipe);
                    if (ds != null) {
                        publishIdRange(pipe, ds);
                        ds.close();
                    }
                    updateStatus(pipe.getRunId(), "DONE");
                } catch (Exception e) {
                    if (ds != null) ds.close();
                    updateStatus(pipe.getRunId(), "FAILED");
                    throw e;
                }
            } catch (Exception e) {
                if (Thread.currentThread().isInterrupted()) break;
                System.err.printf("Worker error: %s%n", e.getMessage());
            }
        }

        System.out.println("Worker stopped.");
    }

    private void resolveFkRanges(PipeDefinition pipe) {
        String db = pipe.getTargetDatabase();
        if (db == null) return;
        for (PipeDefinition.ColumnDefinition col : pipe.getColumns()) {
            if ("FK_INT".equals(col.getType()) && col.getRefTable() != null) {
                queue.lookupIdRange(db, col.getRefTable()).ifPresentOrElse(
                    range -> {
                        col.setValues(java.util.List.of(
                            String.valueOf(range[0]), String.valueOf(range[1])));
                        System.out.printf("Resolved FK range for %s.%s → [%d, %d]%n",
                            pipe.getTargetTable(), col.getName(), range[0], range[1]);
                    },
                    () -> System.out.printf(
                        "No id range found for parent '%s' — using fallback values for %s.%s%n",
                        col.getRefTable(), pipe.getTargetTable(), col.getName())
                );
            }
        }
    }

    private void publishIdRange(PipeDefinition pipe, HikariDataSource ds) {
        String pkCol = pipe.getPkColumn();
        if (pkCol == null || pipe.getTargetDatabase() == null) return;
        String sql = String.format("SELECT MIN(%s), MAX(%s) FROM %s", pkCol, pkCol, pipe.getTargetTable());
        try (java.sql.Connection conn = ds.getConnection();
             java.sql.PreparedStatement ps = conn.prepareStatement(sql);
             java.sql.ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                long min = rs.getLong(1);
                long max = rs.getLong(2);
                queue.publishIdRange(pipe.getTargetDatabase(), pipe.getTargetTable(), min, max);
            }
        } catch (java.sql.SQLException e) {
            System.err.printf("Failed to publish id range for %s: %s%n", pipe.getTargetTable(), e.getMessage());
        }
    }

    private void updateStatus(String runId, String status) {
        if (runId != null && runRepository != null) {
            runRepository.updateStatus(runId, status);
        }
        runMetrics.increment(status);
    }
}
