package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;
import org.apache.avro.Schema;
import org.apache.avro.SchemaBuilder;

public class AvroSchemaBuilder {

    public static Schema buildSchema(PipeDefinition pipe) {
        String name = toAvroName(pipe.getPipeName());
        SchemaBuilder.FieldAssembler<Schema> fields =
                SchemaBuilder.record(name).namespace("com.testfixtures").fields();

        for (PipeDefinition.ColumnDefinition col : pipe.getColumns()) {
            addField(fields, col);
        }

        return fields.endRecord();
    }

    private static void addField(SchemaBuilder.FieldAssembler<Schema> fields,
                                  PipeDefinition.ColumnDefinition col) {
        String name = col.getName();
        switch (col.getType()) {
            case "SEQUENCE"                                    -> fields.requiredLong(name);
            case "RANDOM_INT", "FK_INT", "NULLABLE_FK_INT"    -> fields.optionalInt(name);
            case "BOOLEAN"                                     -> fields.optionalBoolean(name);
            case "NULL_VALUE"                                  -> fields.name(name).type().nullType().nullDefault();
            default                                            -> fields.optionalString(name);
        }
    }

    private static String toAvroName(String pipeName) {
        String sanitized = pipeName.replaceAll("[^A-Za-z0-9_]", "_");
        return Character.isLetter(sanitized.charAt(0)) ? sanitized : "_" + sanitized;
    }
}
