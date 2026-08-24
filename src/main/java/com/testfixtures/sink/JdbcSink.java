package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;
import com.zaxxer.hikari.HikariDataSource;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

public class JdbcSink implements DataSink {

    private static final Set<String> UUID_TYPES = Set.of("UUID", "FK_UUID", "NULLABLE_FK_UUID");

    private final HikariDataSource dataSource;

    public JdbcSink(HikariDataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Override
    public int write(List<Map<String, Object>> rows, PipeDefinition pipe) throws Exception {
        List<String> colNames = pipe.getColumns().stream()
                .map(PipeDefinition.ColumnDefinition::getName)
                .toList();
        // FakerEngine hands UUID/FK_UUID columns to every sink as plain Strings
        // (Kafka/Avro needs a CharSequence, not a java.util.UUID), but the
        // Postgres JDBC driver won't auto-cast a String to a `uuid` column via
        // the generic setObject(idx, value) below — it has to be told the
        // target SQL type explicitly, or handed an actual java.util.UUID.
        Set<Integer> uuidColumns  = new java.util.HashSet<>();
        Set<Integer> arrayColumns = new java.util.HashSet<>();
        for (int j = 0; j < pipe.getColumns().size(); j++) {
            String type = pipe.getColumns().get(j).getType();
            if (UUID_TYPES.contains(type))  uuidColumns.add(j);
            if ("TEXT_ARRAY".equals(type))  arrayColumns.add(j);
        }
        String placeholders = colNames.stream().map(c -> "?").collect(Collectors.joining(", "));
        String sql = String.format("INSERT INTO %s (%s) VALUES (%s) ON CONFLICT DO NOTHING",
                pipe.getTargetTable(), String.join(", ", colNames), placeholders);

        int batchSize = pipe.getBatchSize();
        ExecutorService executor = Executors.newFixedThreadPool(pipe.getConcurrency());
        AtomicInteger rowsInserted = new AtomicInteger(0);
        List<Future<?>> futures = new ArrayList<>();

        for (int i = 0; i < rows.size(); i += batchSize) {
            List<Map<String, Object>> batch = List.copyOf(rows.subList(i, Math.min(i + batchSize, rows.size())));
            int batchStart = i + 1;
            int batchEnd = batchStart + batch.size() - 1;

            futures.add(executor.submit(() -> {
                try (Connection conn = dataSource.getConnection();
                     PreparedStatement stmt = conn.prepareStatement(sql)) {
                    for (Map<String, Object> row : batch) {
                        for (int j = 0; j < colNames.size(); j++) {
                            Object value = row.get(colNames.get(j));
                            if (uuidColumns.contains(j)) {
                                if (value == null) {
                                    stmt.setNull(j + 1, Types.OTHER);
                                } else {
                                    stmt.setObject(j + 1, java.util.UUID.fromString((String) value), Types.OTHER);
                                }
                            } else if (arrayColumns.contains(j)) {
                                if (value == null) {
                                    stmt.setNull(j + 1, Types.ARRAY);
                                } else {
                                    stmt.setArray(j + 1, conn.createArrayOf("text", (String[]) value));
                                }
                            } else {
                                stmt.setObject(j + 1, value);
                            }
                        }
                        stmt.addBatch();
                    }
                    // ON CONFLICT DO NOTHING makes executeBatch()'s per-statement result
                    // the only honest signal — a batch.size() count would silently claim
                    // success for rows that were skipped as duplicates.
                    int[] results = stmt.executeBatch();
                    int affected = 0;
                    for (int r : results) {
                        affected += (r == Statement.SUCCESS_NO_INFO) ? 1 : Math.max(r, 0);
                    }
                    rowsInserted.addAndGet(affected);
                    System.out.printf("Inserted rows %d-%d into %s (%d of %d actually written)%n",
                            batchStart, batchEnd, pipe.getTargetTable(), affected, batch.size());
                } catch (SQLException e) {
                    System.err.println("JdbcSink batch error [" + e.getSQLState() + "]: " + e.getMessage());
                    throw new RuntimeException(e);
                }
            }));
        }

        executor.shutdown();
        for (Future<?> f : futures) {
            f.get();
        }
        System.out.printf("Done: %d rows inserted into %s%n", rowsInserted.get(), pipe.getTargetTable());
        return rowsInserted.get();
    }
}
