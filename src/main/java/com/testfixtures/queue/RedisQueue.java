package com.testfixtures.queue;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.testfixtures.model.PipeDefinition;
import io.lettuce.core.KeyValue;
import io.lettuce.core.RedisClient;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;

import java.util.Optional;

public class RedisQueue implements AutoCloseable {

    private static final String QUEUE_PREFIX   = "testfixtures:queue:";
    private static final String IDRANGE_PREFIX = "testfixtures:idrange:";
    private static final String SEQ_PREFIX     = "testfixtures:seq:";
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final RedisClient client;
    private final StatefulRedisConnection<String, String> connection;
    private final RedisCommands<String, String> commands;

    public RedisQueue(String redisUri) {
        this.client = RedisClient.create(redisUri);
        this.connection = client.connect();
        this.commands = connection.sync();
    }

    public static String queueKey(String domain) {
        return QUEUE_PREFIX + domain.toLowerCase();
    }

    public static final String CSV_DOMAIN     = "csv";
    public static final String PARQUET_DOMAIN = "parquet";
    public static final String KAFKA_DOMAIN   = "kafka";

    public void enqueue(PipeDefinition pipe) throws Exception {
        String domain = resolveDomain(pipe);
        String json = MAPPER.writeValueAsString(pipe);
        commands.lpush(queueKey(domain), json);
        System.out.printf("Enqueued pipe '%s' onto queue '%s'%n", pipe.getPipeName(), queueKey(domain));
    }

    private static String resolveDomain(PipeDefinition pipe) {
        String targetType = pipe.getTargetType() != null ? pipe.getTargetType().toUpperCase() : "JDBC";
        return switch (targetType) {
            case "CSV"     -> CSV_DOMAIN;
            case "PARQUET" -> PARQUET_DOMAIN;
            case "KAFKA"   -> KAFKA_DOMAIN;
            default -> {
                String domain = pipe.getTargetDatabase();
                if (domain == null || domain.isBlank()) {
                    throw new IllegalArgumentException("Pipe '" + pipe.getPipeName() + "' has no targetDatabase");
                }
                yield domain;
            }
        };
    }

    /**
     * Blocks up to {@code timeoutSeconds} across all domain queues; returns empty on timeout.
     * BRPOP checks keys left-to-right, so the order of {@code domains} sets priority.
     */
    public Optional<PipeDefinition> dequeue(long timeoutSeconds, java.util.Collection<String> domains) throws Exception {
        if (domains.isEmpty()) {
            return Optional.empty();
        }
        String[] keys = domains.stream().map(RedisQueue::queueKey).toArray(String[]::new);
        KeyValue<String, String> result = commands.brpop(timeoutSeconds, keys);
        if (result == null || result.isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(MAPPER.readValue(result.getValue(), PipeDefinition.class));
    }

    /**
     * Atomically reserves a contiguous PK range of {@code count} values for the given table.
     * Returns the sequence offset (exclusive lower bound) so callers generate rows
     * [offset+1 .. offset+count]. Multiple concurrent workers always get non-overlapping ranges.
     */
    public long reserveSequenceRange(String database, String table, long count) {
        String key = SEQ_PREFIX + database.toLowerCase() + ":" + table.toLowerCase();
        return commands.incrby(key, count) - count;
    }

    public void publishIdRange(String database, String table, long min, long max) {
        String key = IDRANGE_PREFIX + database.toLowerCase() + ":" + table.toLowerCase();
        commands.hset(key, java.util.Map.of("min", String.valueOf(min), "max", String.valueOf(max)));
        System.out.printf("Published id range for %s.%s: [%d, %d]%n", database, table, min, max);
    }

    public java.util.Optional<long[]> lookupIdRange(String database, String table) {
        String key = IDRANGE_PREFIX + database.toLowerCase() + ":" + table.toLowerCase();
        java.util.Map<String, String> fields = commands.hgetall(key);
        if (fields == null || !fields.containsKey("min") || !fields.containsKey("max")) {
            return java.util.Optional.empty();
        }
        return java.util.Optional.of(new long[]{
            Long.parseLong(fields.get("min")),
            Long.parseLong(fields.get("max"))
        });
    }

    @Override
    public void close() {
        connection.close();
        client.shutdown();
    }
}
