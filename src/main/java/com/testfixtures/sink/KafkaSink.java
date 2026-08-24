package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringSerializer;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.Future;

public class KafkaSink implements DataSink {

    private final String bootstrapServers;
    private final String schemaRegistryUrl;

    public KafkaSink(String bootstrapServers, String schemaRegistryUrl) {
        this.bootstrapServers = bootstrapServers;
        this.schemaRegistryUrl = schemaRegistryUrl;
    }

    @Override
    public int write(List<Map<String, Object>> rows, PipeDefinition pipe) throws Exception {
        String topic = pipe.getTargetTable() != null ? pipe.getTargetTable() : pipe.getPipeName();
        Schema schema = AvroSchemaBuilder.buildSchema(pipe);

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class.getName());
        props.put(AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, schemaRegistryUrl);
        props.put(ProducerConfig.ACKS_CONFIG, "1");
        props.put(ProducerConfig.LINGER_MS_CONFIG, "5");
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, 65536);

        try (KafkaProducer<String, GenericRecord> producer = new KafkaProducer<>(props)) {
            List<Future<RecordMetadata>> futures = new ArrayList<>(rows.size());
            for (int i = 0; i < rows.size(); i++) {
                GenericRecord record = toRecord(schema, pipe.getColumns(), rows.get(i));
                futures.add(producer.send(new ProducerRecord<>(topic, String.valueOf(i + 1), record)));
            }
            for (Future<RecordMetadata> f : futures) {
                f.get();
            }
            System.out.printf("Produced %d Avro messages to topic '%s'%n", rows.size(), topic);
        }
        return rows.size();
    }

    private static GenericRecord toRecord(Schema schema, List<PipeDefinition.ColumnDefinition> cols,
                                           Map<String, Object> row) {
        GenericRecord record = new GenericData.Record(schema);
        for (PipeDefinition.ColumnDefinition col : cols) {
            record.put(col.getName(), toAvroValue(col.getType(), row.get(col.getName())));
        }
        return record;
    }

    private static Object toAvroValue(String colType, Object raw) {
        if (raw == null) return null;
        return switch (colType) {
            case "SEQUENCE"                                    -> ((Number) raw).longValue();
            case "RANDOM_INT", "FK_INT", "NULLABLE_FK_INT"    -> ((Number) raw).intValue();
            case "BOOLEAN"                           -> raw;
            case "NULL_VALUE"                        -> null;
            case "DATE_PAST"                         -> raw.toString();
            case "CURRENCY_AMOUNT", "SMALL_AMOUNT"   -> ((BigDecimal) raw).toPlainString();
            case "JSONB", "INET"                     -> ((org.postgresql.util.PGobject) raw).getValue();
            // Unlike JSONB/INET, FakerEngine hands TEXT_ARRAY to sinks as a raw
            // String[], not a PGobject — JdbcSink needs the raw array for
            // Connection.createArrayOf(), which needs a live connection this
            // class doesn't have. The Avro field for this type is a plain
            // string (AvroSchemaBuilder has no array case), so it has to be
            // flattened to Postgres's own array-literal text form here —
            // {"a","b"} — which KafkaConsumerService.fromAvro then hands
            // straight to a PGobject("text[]", ...) on the way back in.
            case "TEXT_ARRAY"                        -> textArrayLiteral((String[]) raw);
            default                                  -> raw.toString();
        };
    }

    /** Postgres array-literal text form: {"a","b"} — each element double-quoted
     *  and escaped so values containing commas/braces/quotes still round-trip. */
    private static String textArrayLiteral(String[] values) {
        StringBuilder sb = new StringBuilder("{");
        for (int i = 0; i < values.length; i++) {
            if (i > 0) sb.append(',');
            sb.append('"').append(values[i].replace("\\", "\\\\").replace("\"", "\\\"")).append('"');
        }
        return sb.append('}').toString();
    }
}
