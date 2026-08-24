package com.testfixtures.loader;

import com.github.javafaker.Faker;
import com.testfixtures.generator.FakerEngine;
import com.testfixtures.model.PipeDefinition;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class RowGenerator {

    public static List<Map<String, Object>> generate(PipeDefinition pipe) {
        List<PipeDefinition.ColumnDefinition> columns = pipe.getColumns();
        FakerEngine engine = new FakerEngine(new Faker());
        long offset = pipe.getSequenceOffset();
        List<Map<String, Object>> rows = new ArrayList<>(pipe.getTotalRows());
        for (long seq = offset + 1; seq <= offset + pipe.getTotalRows(); seq++) {
            Map<String, Object> row = new LinkedHashMap<>();
            for (PipeDefinition.ColumnDefinition col : columns) {
                row.put(col.getName(), engine.generate(col, seq, pipe.getTargetTable()));
            }
            rows.add(row);
        }
        return rows;
    }
}
