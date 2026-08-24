package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;
import org.apache.avro.Schema;
import org.apache.avro.SchemaBuilder;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.parquet.avro.AvroParquetWriter;
import org.apache.parquet.hadoop.ParquetWriter;
import org.apache.parquet.hadoop.metadata.CompressionCodecName;

import java.math.BigDecimal;
import java.nio.file.Files;
import java.util.List;
import java.util.Map;

public class ParquetSink implements DataSink {

    private final String outputDir;

    public ParquetSink(String outputDir) {
        this.outputDir = outputDir;
    }

    @Override
    public int write(List<Map<String, Object>> rows, PipeDefinition pipe) throws Exception {
        java.nio.file.Path dir = java.nio.file.Path.of(outputDir);
        Files.createDirectories(dir);

        String filename = resolveName(pipe) + ".parquet";
        java.nio.file.Path outFile = dir.resolve(filename);
        Files.deleteIfExists(outFile);

        Schema schema = buildSchema(pipe);

        Configuration conf = new Configuration();
        conf.set("fs.defaultFS", "file:///");
        Path hadoopPath = new Path(outFile.toAbsolutePath().toString());

        try (ParquetWriter<GenericRecord> writer = AvroParquetWriter.<GenericRecord>builder(hadoopPath)
                .withSchema(schema)
                .withConf(conf)
                .withCompressionCodec(CompressionCodecName.SNAPPY)
                .build()) {

            for (Map<String, Object> row : rows) {
                GenericRecord record = new GenericData.Record(schema);
                for (PipeDefinition.ColumnDefinition col : pipe.getColumns()) {
                    record.put(col.getName(), coerce(row.get(col.getName()), col.getType()));
                }
                writer.write(record);
            }
        }

        System.out.printf("Wrote %d rows to %s%n", rows.size(), outFile.toAbsolutePath());
        return rows.size();
    }

    private static Schema buildSchema(PipeDefinition pipe) {
        SchemaBuilder.FieldAssembler<Schema> fields =
                SchemaBuilder.record("Row").namespace("com.testfixtures").fields();
        for (PipeDefinition.ColumnDefinition col : pipe.getColumns()) {
            fields = switch (col.getType()) {
                case "SEQUENCE"                              -> fields.name(col.getName()).type().longType().noDefault();
                case "RANDOM_INT", "FK_INT", "NULLABLE_FK_INT" -> fields.name(col.getName()).type().intType().noDefault();
                case "CURRENCY_AMOUNT", "SMALL_AMOUNT"       -> fields.name(col.getName()).type().doubleType().noDefault();
                default                                      -> fields.name(col.getName()).type().stringType().noDefault();
            };
        }
        return fields.endRecord();
    }

    private static Object coerce(Object value, String type) {
        if (value == null) return null;
        return switch (type) {
            case "SEQUENCE"                              -> ((Number) value).longValue();
            case "RANDOM_INT", "FK_INT", "NULLABLE_FK_INT" -> ((Number) value).intValue();
            case "CURRENCY_AMOUNT", "SMALL_AMOUNT"       -> ((BigDecimal) value).doubleValue();
            default                                      -> value.toString();
        };
    }

    private static String resolveName(PipeDefinition pipe) {
        String name = pipe.getPipeName();
        if (name != null && !name.isBlank()) return name;
        return pipe.getTargetTable();
    }
}
