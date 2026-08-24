package com.testfixtures.model;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Data;

import java.util.List;

@Data
@JsonInclude(JsonInclude.Include.NON_NULL)
public class PipeDefinition {

    private String runId;
    private String pipeName;
    private String targetDatabase;
    private String targetTable;
    private String targetType = "JDBC";
    private String pkColumn;
    private long sequenceOffset = 0;
    private int batchSize;
    private int totalRows;
    private int concurrency;
    private List<ColumnDefinition> columns;

    @Data
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public static class ColumnDefinition {
        private String name;
        private String type;
        private List<String> values;
        private String refTable;
    }
}
