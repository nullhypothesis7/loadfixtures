package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

public class CsvSink implements DataSink {

    private final String outputDir;

    public CsvSink(String outputDir) {
        this.outputDir = outputDir;
    }

    @Override
    public int write(List<Map<String, Object>> rows, PipeDefinition pipe) throws Exception {
        Path dir = Path.of(outputDir);
        Files.createDirectories(dir);

        String filename = resolveName(pipe) + ".csv";
        Path file = dir.resolve(filename);

        List<String> colNames = pipe.getColumns().stream()
                .map(PipeDefinition.ColumnDefinition::getName)
                .toList();

        try (BufferedWriter writer = Files.newBufferedWriter(file, StandardCharsets.UTF_8)) {
            writer.write(toCsvLine(colNames.stream().map(Object.class::cast).toList()));
            writer.newLine();
            for (Map<String, Object> row : rows) {
                List<Object> values = colNames.stream().map(row::get).toList();
                writer.write(toCsvLine(values));
                writer.newLine();
            }
        }

        System.out.printf("Wrote %d rows to %s%n", rows.size(), file.toAbsolutePath());
        return rows.size();
    }

    private static String resolveName(PipeDefinition pipe) {
        String name = pipe.getPipeName();
        if (name != null && !name.isBlank()) return name;
        return pipe.getTargetTable();
    }

    private static String toCsvLine(List<Object> values) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) sb.append(',');
            sb.append(quoteField(values.get(i)));
        }
        return sb.toString();
    }

    private static String quoteField(Object value) {
        if (value == null) return "\"\"";
        String s = value.toString();
        // RFC 4180: wrap in quotes, escape internal quotes by doubling
        return "\"" + s.replace("\"", "\"\"") + "\"";
    }
}
