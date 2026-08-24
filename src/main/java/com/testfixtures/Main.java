package com.testfixtures;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.testfixtures.config.AppConfig;
import com.testfixtures.loader.RowGenerator;
import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.sink.CsvSink;
import com.testfixtures.sink.DataSink;
import com.testfixtures.sink.JdbcSink;
import com.testfixtures.sink.ParquetSink;
import com.testfixtures.queue.QueueWorker;
import com.testfixtures.queue.RedisQueue;
import com.testfixtures.repository.RunRepository;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;

import java.io.File;
import java.util.List;

@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)
public class Main implements ApplicationRunner {

    private final RedisQueue redisQueue;
    private final RunRepository runRepository;
    private final RunMetrics runMetrics;

    public Main(RedisQueue redisQueue, RunRepository runRepository, RunMetrics runMetrics) {
        this.redisQueue = redisQueue;
        this.runRepository = runRepository;
        this.runMetrics = runMetrics;
    }

    public static void main(String[] args) {
        SpringApplication app = new SpringApplication(Main.class);
        if (args.length > 0) {
            app.setWebApplicationType(WebApplicationType.NONE);
        }
        app.run(args);
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        List<String> positional = args.getNonOptionArgs();
        if (positional.isEmpty()) {
            AppConfig config = AppConfig.fromEnv();
            QueueWorker worker = new QueueWorker(redisQueue, config, runRepository, runMetrics);
            Thread workerThread = new Thread(worker::run, "queue-worker");
            workerThread.setDaemon(true);
            workerThread.start();
            return;
        }

        switch (positional.get(0)) {
            case "enqueue" -> {
                if (positional.size() < 2) { printUsage(); System.exit(1); }
                redisQueue.enqueue(loadPipe(positional.get(1)));
                System.exit(0);
            }
            case "worker" -> {
                AppConfig config = AppConfig.fromEnv();
                QueueWorker worker = new QueueWorker(redisQueue, config, runRepository, runMetrics);
                Runtime.getRuntime().addShutdownHook(new Thread(worker::stop));
                worker.run();
            }
            default -> {
                PipeDefinition pipe = loadPipe(positional.get(0));
                AppConfig config = AppConfig.fromEnv();
                System.out.printf("Loading pipe: %s — %d rows into %s (concurrency=%d, batchSize=%d)%n",
                        pipe.getPipeName(), pipe.getTotalRows(), pipe.getTargetTable(),
                        pipe.getConcurrency(), pipe.getBatchSize());
                String targetType = pipe.getTargetType() != null ? pipe.getTargetType().toUpperCase() : "JDBC";
                if ("CSV".equals(targetType)) {
                    List<java.util.Map<String, Object>> rows = RowGenerator.generate(pipe);
                    DataSink sink = new CsvSink(config.getCsvOutputDir());
                    sink.write(rows, pipe);
                } else if ("PARQUET".equals(targetType)) {
                    List<java.util.Map<String, Object>> rows = RowGenerator.generate(pipe);
                    DataSink sink = new ParquetSink(config.getParquetOutputDir());
                    sink.write(rows, pipe);
                } else if ("JDBC".equals(targetType)) {
                    try (HikariDataSource dataSource = buildDataSource(config, pipe, pipe.getConcurrency() + 1)) {
                        resolveFkRangesFromDb(pipe, dataSource);
                        List<java.util.Map<String, Object>> rows = RowGenerator.generate(pipe);
                        DataSink sink = new JdbcSink(dataSource);
                        sink.write(rows, pipe);
                    }
                } else {
                    System.err.printf("Unsupported targetType '%s' — only JDBC, CSV, and PARQUET are supported%n", pipe.getTargetType());
                    System.exit(1);
                }
                System.exit(0);
            }
        }
    }

    private static PipeDefinition loadPipe(String path) throws Exception {
        return new ObjectMapper().readValue(new File(path), PipeDefinition.class);
    }

    private static HikariDataSource buildDataSource(AppConfig config, PipeDefinition pipe, int poolSize) {
        String db = pipe.getTargetDatabase() != null ? pipe.getTargetDatabase().toLowerCase() : "";
        String url  = config.getDatabaseUrls().getOrDefault(db, config.getJdbcUrl());
        String user = config.getDatabaseUsers().getOrDefault(db, config.getUsername());
        String pass = config.getDatabasePasswords().getOrDefault(db, config.getPassword());
        HikariConfig hc = new HikariConfig();
        hc.setJdbcUrl(url);
        hc.setUsername(user);
        hc.setPassword(pass);
        hc.setMaximumPoolSize(poolSize);
        return new HikariDataSource(hc);
    }

    private static void resolveFkRangesFromDb(PipeDefinition pipe, HikariDataSource ds) {
        for (PipeDefinition.ColumnDefinition col : pipe.getColumns()) {
            if ((!"FK_INT".equals(col.getType()) && !"NULLABLE_FK_INT".equals(col.getType()))
                    || col.getRefTable() == null) {
                continue;
            }
            String pkCol = queryPkColumn(ds, col.getRefTable());
            if (pkCol == null) continue;
            String sql = String.format("SELECT MIN(%s), MAX(%s) FROM %s", pkCol, pkCol, col.getRefTable());
            try (java.sql.Connection conn = ds.getConnection();
                 java.sql.PreparedStatement ps = conn.prepareStatement(sql);
                 java.sql.ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    long min = rs.getLong(1);
                    long max = rs.getLong(2);
                    if (!rs.wasNull() && max > 0) {
                        col.setValues(List.of(String.valueOf(min), String.valueOf(max)));
                        System.out.printf("Resolved FK range for %s.%s → [%d, %d]%n",
                                pipe.getTargetTable(), col.getName(), min, max);
                    }
                }
            } catch (java.sql.SQLException e) {
                System.err.printf("Could not resolve FK range for %s: %s%n", col.getRefTable(), e.getMessage());
            }
        }
    }

    private static String queryPkColumn(HikariDataSource ds, String schemaTable) {
        String[] parts = schemaTable.split("\\.", 2);
        String schema = parts.length == 2 ? parts[0] : "public";
        String table  = parts.length == 2 ? parts[1] : parts[0];
        String sql = """
                SELECT kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema    = kcu.table_schema
                WHERE tc.table_schema    = ?
                  AND tc.table_name      = ?
                  AND tc.constraint_type = 'PRIMARY KEY'
                LIMIT 1
                """;
        try (java.sql.Connection conn = ds.getConnection();
             java.sql.PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, schema);
            ps.setString(2, table);
            try (java.sql.ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getString(1) : null;
            }
        } catch (java.sql.SQLException e) {
            System.err.printf("Could not find PK for %s: %s%n", schemaTable, e.getMessage());
            return null;
        }
    }

    private static void printUsage() {
        System.out.println("Usage:");
        System.out.println("  testfixtures <pipe.json>          run directly against DB");
        System.out.println("  testfixtures enqueue <pipe.json>  push job onto Redis queue");
        System.out.println("  testfixtures worker               consume jobs from Redis queue");
    }
}
