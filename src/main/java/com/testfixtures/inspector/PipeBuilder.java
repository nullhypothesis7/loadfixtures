package com.testfixtures.inspector;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.testfixtures.model.PipeDefinition;

import java.io.IOException;
import java.io.InputStream;
import java.util.*;

/**
 * Shared logic for converting intermediate table metadata into PipeDefinitions.
 * Used by both SchemaInspector (live DB) and DdlInspector (DDL text).
 */
class PipeBuilder {

    static final int DEFAULT_BATCH_SIZE  = 100;
    static final int DEFAULT_TOTAL_ROWS  = 1000;
    static final int DEFAULT_CONCURRENCY = 1;

    // Bare table name -> Salesforce 18-char record Id key prefix. Unlike
    // "uuid", Postgres has no native type that self-describes a column as
    // "a Salesforce-shaped Id" — a CHAR(18)/VARCHAR(18) column looks
    // identical to any other string column whether it's schema-inspected
    // live or parsed from DDL text. This sidecar map is the deliberate
    // alternative to hand-authoring pipe JSON per table: onboarding another
    // Salesforce (or Salesforce-derived) object is one line here, not a
    // full column-by-column pipe definition. mapColumn() below only treats
    // a CHAR/VARCHAR(15|18) PK/FK column as SF_ID/FK_SF_ID when its table is
    // actually listed here, so this can't misfire against an unrelated
    // schema's CHAR(18) columns unless a table name collides with one of
    // these entries *and* happens to use a 15/18-char string key — accepted
    // as an unlikely edge case given how uncommon that PK shape is outside
    // Salesforce-derived schemas.
    private static final Map<String, String> SF_KEY_PREFIXES = loadSalesforceKeyPrefixes();

    private static Map<String, String> loadSalesforceKeyPrefixes() {
        try (InputStream in = PipeBuilder.class.getResourceAsStream("/salesforce-key-prefixes.json")) {
            if (in == null) return Map.of();
            return new ObjectMapper().readValue(in, new TypeReference<Map<String, String>>() {});
        } catch (IOException e) {
            throw new RuntimeException("Failed to load salesforce-key-prefixes.json", e);
        }
    }

    /** @return the mapped Salesforce key prefix for this (possibly schema-qualified) table, or null if unmapped. */
    static String salesforceKeyPrefix(String schemaTable) {
        int dot = schemaTable.lastIndexOf('.');
        String bare = dot >= 0 ? schemaTable.substring(dot + 1) : schemaTable;
        return SF_KEY_PREFIXES.get(bare);
    }

    static boolean isSfIdShaped(String pgType, Integer charMaxLength) {
        boolean isCharish = "character".equals(pgType) || "character varying".equals(pgType)
                          || "text".equals(pgType);
        return isCharish && (charMaxLength == null || charMaxLength == 15 || charMaxLength == 18);
    }

    record RawColumn(String name, String dataType, String udtName,
                     String columnDefault, Integer characterMaxLength,
                     Integer numericPrecision, Integer numericScale,
                     boolean isNullable) {}

    record FkEdge(String child, String childColumn, String parent, String parentColumn) {}

    record FkTarget(String parentTable, boolean isStringFk) {}

    static List<PipeDefinition> buildPipes(
            Set<String> tables,
            Map<String, List<RawColumn>> colsByTable,
            Map<String, Set<String>> pksByTable,
            Map<String, Set<String>> uniquesByTable,
            List<FkEdge> fks,
            Map<String, Map<String, List<String>>> checkEnumsByTable,
            String targetDatabase) {

        Map<String, Map<String, FkTarget>> fkColumns = new HashMap<>();
        for (FkEdge e : fks) {
            Set<String> parentPks  = pksByTable.getOrDefault(e.parent(), Set.of());
            Set<String> parentUniq = uniquesByTable.getOrDefault(e.parent(), Set.of());
            boolean isParentColUniqueString = !parentPks.contains(e.parentColumn())
                                              && parentUniq.contains(e.parentColumn());
            fkColumns.computeIfAbsent(e.child(), t -> new HashMap<>())
                     .put(e.childColumn(), new FkTarget(e.parent(), isParentColUniqueString));
        }

        List<String> ordered = topologicalSort(tables, fks);

        List<PipeDefinition> pipes = new ArrayList<>();
        for (String table : ordered) {
            pipes.add(buildPipe(
                    table, targetDatabase,
                    colsByTable.getOrDefault(table, List.of()),
                    pksByTable.getOrDefault(table, Set.of()),
                    uniquesByTable.getOrDefault(table, Set.of()),
                    checkEnumsByTable.getOrDefault(table, Map.of()),
                    fkColumns.getOrDefault(table, Map.of())));
        }
        return pipes;
    }

    static List<String> topologicalSort(Set<String> tables, List<FkEdge> edges) {
        Map<String, Set<String>> parents  = new HashMap<>();
        Map<String, Set<String>> children = new HashMap<>();
        for (String t : tables) {
            parents.put(t, new HashSet<>());
            children.put(t, new HashSet<>());
        }
        for (FkEdge e : edges) {
            if (!e.child().equals(e.parent())
                    && tables.contains(e.child())
                    && tables.contains(e.parent())) {
                parents.get(e.child()).add(e.parent());
                children.get(e.parent()).add(e.child());
            }
        }

        Queue<String> ready = new PriorityQueue<>();
        for (String t : tables) {
            if (parents.get(t).isEmpty()) ready.add(t);
        }

        Set<String> ordered = new LinkedHashSet<>();
        while (!ready.isEmpty()) {
            String t = ready.poll();
            ordered.add(t);
            for (String child : children.get(t)) {
                parents.get(child).remove(t);
                if (parents.get(child).isEmpty()) ready.add(child);
            }
        }
        ordered.addAll(tables);
        return new ArrayList<>(ordered);
    }

    private static PipeDefinition buildPipe(String schemaTable, String targetDatabase,
                                            List<RawColumn> cols, Set<String> pks,
                                            Set<String> uniqueCols,
                                            Map<String, List<String>> checkEnums,
                                            Map<String, FkTarget> fkCols) {
        PipeDefinition pipe = new PipeDefinition();
        pipe.setTargetTable(schemaTable);
        pipe.setPipeName(targetDatabase + "-" + schemaTable.replace('.', '-'));
        pipe.setTargetDatabase(targetDatabase);
        pipe.setTargetType("JDBC");
        pipe.setBatchSize(DEFAULT_BATCH_SIZE);
        pipe.setTotalRows(DEFAULT_TOTAL_ROWS);
        pipe.setConcurrency(DEFAULT_CONCURRENCY);
        pipe.setColumns(cols.stream()
                .map(c -> {
                    FkTarget fkTarget = fkCols.get(c.name());
                    if (fkTarget != null && fkTarget.parentTable().equals(schemaTable)) {
                        if (c.isNullable()) {
                            PipeDefinition.ColumnDefinition nullDef = new PipeDefinition.ColumnDefinition();
                            nullDef.setName(c.name());
                            nullDef.setType("NULL_VALUE");
                            return nullDef;
                        }
                        fkTarget = null;
                    }
                    return mapColumn(c, pks.contains(c.name()),
                            !pks.contains(c.name()) && uniqueCols.contains(c.name()),
                            checkEnums.get(c.name()),
                            fkTarget,
                            c.isNullable(),
                            schemaTable);
                })
                .toList());

        if (pks.size() == 1) {
            String pk = pks.iterator().next();
            cols.stream()
                .filter(c -> c.name().equals(pk) && isIntType(c.dataType()))
                .findFirst()
                .ifPresent(c -> pipe.setPkColumn(pk));
        }
        return pipe;
    }

    static PipeDefinition.ColumnDefinition mapColumn(RawColumn col, boolean isPk,
                                                     boolean isUnique,
                                                     List<String> checkValues,
                                                     FkTarget fkTarget,
                                                     boolean nullable,
                                                     String ownTable) {
        PipeDefinition.ColumnDefinition def = new PipeDefinition.ColumnDefinition();
        def.setName(col.name());

        String pgType   = col.dataType();
        String colName  = col.name().toLowerCase();
        boolean isSeq   = col.columnDefault() != null && col.columnDefault().startsWith("nextval(");
        String parentTable = fkTarget != null ? fkTarget.parentTable() : null;

        // FK-ness takes precedence over PK-ness: a column can be both (the
        // member of a composite primary key that's also a foreign key into
        // another table, e.g. a many-to-many junction table's two columns).
        // Checking this first — rather than only inside the plain isIntType
        // branch further down — is what makes that combination resolve
        // against the parent table's actual rows instead of silently being
        // treated as a fresh, unrelated SEQUENCE/UUID.
        //
        // Deliberately excludes isUnique: a column that's UNIQUE *and* an FK
        // is a 1-to-1 relationship, and FK_INT/FK_UUID's "pick a random
        // index in range" strategy isn't safe there — repeated picks collide
        // against the unique constraint, ON CONFLICT silently drops those
        // rows, and the parent ends up with gaps that break other children's
        // FK resolution later (found via bank_schema's card_account.account_id
        // regressing SchemaIntegrationTest). Composite-PK members are never
        // separately flagged isUnique in this model, so this doesn't affect
        // that fix. A real 1-to-1 generator would need a non-repeating
        // parent-index assignment, not attempted here.
        if (parentTable != null && !isUnique && (isIntType(pgType) || isSeq)) {
            def.setType(nullable ? "NULLABLE_FK_INT" : "FK_INT");
            def.setRefTable(parentTable);
            def.setValues(List.of("1", String.valueOf(DEFAULT_TOTAL_ROWS)));
        } else if (parentTable != null && !isUnique && "uuid".equals(pgType)) {
            def.setType(nullable ? "NULLABLE_FK_UUID" : "FK_UUID");
            def.setRefTable(parentTable);
            def.setValues(List.of("1", String.valueOf(DEFAULT_TOTAL_ROWS)));
        } else if (parentTable != null && !isUnique
                   && isSfIdShaped(pgType, col.characterMaxLength())
                   && salesforceKeyPrefix(parentTable) != null) {
            // Same "recompute the parent's exact PK from a chosen row index"
            // trick as FK_UUID, generalized to a fixed-format checksum-suffixed
            // scheme instead of a UUID — see FakerEngine.salesforceId(). The
            // parent's key prefix travels through values[2] rather than being
            // re-looked-up in FakerEngine, so the sidecar map has exactly one
            // reader (this class) instead of being duplicated across packages.
            def.setType(nullable ? "NULLABLE_FK_SF_ID" : "FK_SF_ID");
            def.setRefTable(parentTable);
            def.setValues(List.of("1", String.valueOf(DEFAULT_TOTAL_ROWS), salesforceKeyPrefix(parentTable)));
        } else if (isPk && (isIntType(pgType) || isSeq)) {
            def.setType("SEQUENCE");
        } else if (isPk && "uuid".equals(pgType)) {
            def.setType("UUID");
        } else if (isPk && isSfIdShaped(pgType, col.characterMaxLength())
                   && salesforceKeyPrefix(ownTable) != null) {
            def.setType("SF_ID");
            def.setValues(List.of(salesforceKeyPrefix(ownTable)));
        } else if (isPk && (col.characterMaxLength() == null || col.characterMaxLength() >= 8)) {
            def.setType("UNIQUE_STRING");
        } else if (isUnique && isIntType(pgType)) {
            def.setType("SEQUENCE");
        } else if ("uuid".equals(pgType) || "uuid".equals(col.udtName())) {
            def.setType("UUID");
        } else if ("boolean".equals(pgType)) {
            def.setType("BOOLEAN");
        } else if ("jsonb".equals(pgType) || "json".equals(pgType)) {
            def.setType("JSONB");
        } else if ("inet".equals(pgType) || "cidr".equals(pgType)) {
            def.setType("INET");
        } else if ("ARRAY".equals(pgType)) {
            def.setType("TEXT_ARRAY");
        } else if (isNumericType(pgType)) {
            Integer prec  = col.numericPrecision();
            Integer scale = col.numericScale();
            if (prec != null && scale != null && (prec - scale) <= 3) {
                def.setType("SMALL_AMOUNT");
            } else {
                def.setType("CURRENCY_AMOUNT");
            }
            // CURRENCY_AMOUNT/SMALL_AMOUNT otherwise generate up to a hardcoded
            // 999999.99/99.99 — fine for a loose NUMERIC(12,2), but a genuinely
            // narrow column (NUMERIC(3,2), max 9.99) overflows on the very
            // first insert. Pass the column's real ceiling through so the
            // generator can respect it instead of guessing. The scale travels
            // with it (values[1]) — FakerEngine used to always round to a
            // hardcoded 2 decimal places regardless of the column's actual
            // scale, which could round a value drawn near the ceiling *past*
            // it for any scale != 2 (NUMERIC(5,3): ceiling 99.999, a draw of
            // 99.9987 rounds to 100.00 at 2dp and overflows) — caught live via
            // card.card_product.foreign_txn_fee_pct, not by any prior test.
            if (prec != null && scale != null) {
                double maxValue = Math.pow(10, Math.max(prec - scale, 0)) - Math.pow(10, -scale);
                def.setValues(List.of(String.valueOf(maxValue), String.valueOf(scale)));
            }
        } else if (isDateType(pgType)) {
            def.setType("DATE_PAST");
        } else if (isIntType(pgType)) {
            // parentTable is always null here — the FK case is handled by the
            // top-of-method check, which runs before isPk/isUnique branches
            // can shadow it.
            boolean isSmallInt = "smallint".equals(pgType) || "int2".equals(pgType);
            if (isSmallInt) {
                def.setType("RANDOM_INT");
                def.setValues(List.of("1", "32767"));
            } else {
                def.setType("RANDOM_INT");
                def.setValues(List.of("1", "1000000"));
            }
        } else if (isUnique) {
            def.setType("UNIQUE_STRING");
        } else if (fkTarget != null && fkTarget.isStringFk()) {
            def.setType("STRING_FK");
            def.setValues(List.of("1", String.valueOf(DEFAULT_TOTAL_ROWS)));
        } else if (checkValues != null && !checkValues.isEmpty()) {
            def.setType("ENUM");
            def.setValues(checkValues);
        } else {
            assignStringType(def, colName, col.characterMaxLength());
        }
        return def;
    }

    static void assignStringType(PipeDefinition.ColumnDefinition def, String colName,
                                 Integer maxLength) {
        if (colName.contains("first") && colName.contains("name")) {
            def.setType("FIRST_NAME");
        } else if (colName.contains("last") && colName.contains("name")) {
            def.setType("LAST_NAME");
        } else if (colName.equals("name") || colName.endsWith("_name")) {
            def.setType("FIRST_NAME");
        } else if (colName.contains("email")) {
            if (maxLength != null && maxLength < 50) {
                def.setType("FIRST_NAME");
            } else {
                def.setType("EMAIL");
            }
        } else if (colName.contains("phone")) {
            def.setType("PHONE");
            // Faker's phone formats vary in length (some include an
            // extension, e.g. "1-619-428-8127 x50479") and can exceed a
            // typical VARCHAR(20)-ish phone column; pass the real ceiling
            // through so the generator can bound its output instead of
            // occasionally overflowing at random.
            if (maxLength != null) {
                def.setValues(List.of(String.valueOf(maxLength)));
            }
        } else if (colName.endsWith("_id") || colName.contains("uuid")) {
            if (maxLength != null && maxLength < 36) {
                def.setType("RANDOM_INT");
                def.setValues(List.of("1", "1000000"));
            } else {
                def.setType("UUID");
            }
        } else if (maxLength != null && maxLength <= 20) {
            def.setType("ENUM");
            if (maxLength == 1) {
                def.setValues(List.of("A", "B", "C", "D"));
            } else if (maxLength == 2) {
                def.setValues(List.of("A1", "B2", "C3", "D4"));
            } else {
                def.setValues(List.of("A01", "B02", "C03", "D04"));
            }
        } else {
            def.setType("FIRST_NAME");
        }
    }

    static boolean isIntType(String t) {
        return t.equals("integer") || t.equals("bigint") || t.equals("smallint")
                || t.equals("int") || t.equals("int2") || t.equals("int4") || t.equals("int8");
    }

    static boolean isNumericType(String t) {
        return t.equals("numeric") || t.equals("decimal") || t.equals("money")
                || t.equals("real") || t.equals("double precision");
    }

    static boolean isDateType(String t) {
        return t.equals("date") || t.startsWith("timestamp") || t.startsWith("time");
    }
}
