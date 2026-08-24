package com.testfixtures.consumer;

import com.testfixtures.inspector.SchemaInspector;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.sink.JdbcSink;
import com.zaxxer.hikari.HikariDataSource;
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.postgresql.util.PGobject;

import java.math.BigDecimal;
import java.sql.SQLException;
import java.time.Duration;
import java.util.*;

public class KafkaConsumerService {

    private final String bootstrapServers;
    private final String schemaRegistryUrl;

    public KafkaConsumerService(String bootstrapServers, String schemaRegistryUrl) {
        this.bootstrapServers = bootstrapServers;
        this.schemaRegistryUrl = schemaRegistryUrl;
    }

    public ConsumeResult consume(String targetDatabase, List<String> schemas, HikariDataSource ds) throws Exception {
        List<PipeDefinition> pipes = new SchemaInspector(ds).inspect(targetDatabase, schemas);
        JdbcSink sink = new JdbcSink(ds);

        int totalRows = 0;
        int tablesConsumed = 0;

        for (PipeDefinition pipe : pipes) {
            List<Map<String, Object>> rows = consumeTopic(pipe.getTargetTable(), pipe);
            if (!rows.isEmpty()) {
                totalRows += sink.write(rows, pipe);
                tablesConsumed++;
            }
        }

        return new ConsumeResult(tablesConsumed, totalRows);
    }

    private List<Map<String, Object>> consumeTopic(String topic, PipeDefinition pipe) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "testfixtures-consumer-" + UUID.randomUUID());
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, KafkaAvroDeserializer.class.getName());
        props.put(AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, schemaRegistryUrl);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);

        List<Map<String, Object>> rows = new ArrayList<>();

        try (KafkaConsumer<String, GenericRecord> consumer = new KafkaConsumer<>(props)) {
            TopicPartition tp = new TopicPartition(topic, 0);
            consumer.assign(List.of(tp));
            consumer.seekToBeginning(List.of(tp));

            long endOffset = consumer.endOffsets(List.of(tp)).getOrDefault(tp, 0L);
            if (endOffset == 0) {
                System.out.printf("Topic '%s' is empty — skipping%n", topic);
                return rows;
            }

            while (consumer.position(tp) < endOffset) {
                ConsumerRecords<String, GenericRecord> records = consumer.poll(Duration.ofMillis(500));
                for (var record : records) {
                    rows.add(toRow(record.value(), pipe.getColumns()));
                }
            }
            System.out.printf("Consumed %d messages from topic '%s'%n", rows.size(), topic);

        } catch (Exception e) {
            System.err.printf("Skipping topic '%s': %s%n", topic, e.getMessage());
        }

        return rows;
    }

    private Map<String, Object> toRow(GenericRecord record, List<PipeDefinition.ColumnDefinition> cols) {
        Map<String, Object> row = new LinkedHashMap<>();
        for (PipeDefinition.ColumnDefinition col : cols) {
            row.put(col.getName(), fromAvro(record.get(col.getName()), col.getType()));
        }
        return row;
    }

    private Object fromAvro(Object val, String colType) {
        if (val == null) return null;
        return switch (colType) {
            case "SEQUENCE"                                    -> ((Number) val).longValue();
            case "RANDOM_INT", "FK_INT", "NULLABLE_FK_INT"    -> ((Number) val).intValue();
            case "BOOLEAN"                                     -> val;
            case "CURRENCY_AMOUNT", "SMALL_AMOUNT"             -> new BigDecimal(val.toString());
            case "DATE_PAST"                                   -> java.sql.Date.valueOf(val.toString());
            case "JSONB"                                       -> pgObject("jsonb",   val.toString());
            case "INET"                                        -> pgObject("inet",    val.toString());
            // JdbcSink casts TEXT_ARRAY columns to String[] (needed for
            // Connection.createArrayOf(), the same reason FakerEngine/KafkaSink
            // never wrap this one in a PGobject either) — a PGobject here would
            // throw the same ClassCastException on the way back in that
            // KafkaSink.textArrayLiteral() was added to avoid on the way out.
            // Parse the {"a","b"} literal KafkaSink produced back into an array.
            case "TEXT_ARRAY"                                  -> parseTextArrayLiteral(val.toString());
            default                                            -> val.toString();
        };
    }

    /** Inverse of KafkaSink.textArrayLiteral() — parses Postgres's {"a","b"}
     *  array-literal text form back into a raw String[], handling escaped
     *  quotes/backslashes inside elements and unquoted elements alike. */
    private static String[] parseTextArrayLiteral(String literal) {
        String body = literal.trim();
        if (body.startsWith("{") && body.endsWith("}")) {
            body = body.substring(1, body.length() - 1);
        }
        if (body.isEmpty()) return new String[0];

        List<String> out = new ArrayList<>();
        StringBuilder cur = new StringBuilder();
        boolean inQuotes = false;
        for (int i = 0; i < body.length(); i++) {
            char c = body.charAt(i);
            if (inQuotes) {
                if (c == '\\' && i + 1 < body.length()) {
                    cur.append(body.charAt(++i));
                } else if (c == '"') {
                    inQuotes = false;
                } else {
                    cur.append(c);
                }
            } else if (c == '"') {
                inQuotes = true;
            } else if (c == ',') {
                out.add(cur.toString());
                cur.setLength(0);
            } else {
                cur.append(c);
            }
        }
        out.add(cur.toString());
        return out.toArray(new String[0]);
    }

    private static PGobject pgObject(String type, String value) {
        try {
            PGobject obj = new PGobject();
            obj.setType(type);
            obj.setValue(value);
            return obj;
        } catch (SQLException e) {
            throw new RuntimeException(e);
        }
    }

    public record ConsumeResult(int tablesConsumed, int rowsWritten) {}
}
