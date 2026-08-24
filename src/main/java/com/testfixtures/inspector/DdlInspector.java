package com.testfixtures.inspector;

import com.testfixtures.model.PipeDefinition;
import net.sf.jsqlparser.parser.CCJSqlParserUtil;
import net.sf.jsqlparser.statement.Statement;
import net.sf.jsqlparser.statement.Statements;
import net.sf.jsqlparser.statement.create.table.ColumnDefinition;
import net.sf.jsqlparser.statement.create.table.CreateTable;
import net.sf.jsqlparser.statement.create.table.ForeignKeyIndex;
import net.sf.jsqlparser.statement.create.table.Index;

import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class DdlInspector {

    private static final String DEFAULT_SCHEMA = "public";

    private static final Pattern INLINE_REF = Pattern.compile(
            "REFERENCES\\s+([\\w.]+)\\s*(?:\\(\\s*(\\w+)\\s*\\))?",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern INLINE_CHECK = Pattern.compile(
            "CHECK\\s*\\((.+)\\)$",
            Pattern.CASE_INSENSITIVE | Pattern.DOTALL);
    private static final Pattern ENUM_IN = Pattern.compile(
            "(\\w+)\\s+IN\\s*\\(([^)]+)\\)",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern ENUM_VAL = Pattern.compile("'([^']*)'");

    // jsqlparser's CREATE TABLE grammar doesn't support "CREATE SCHEMA ...";
    // real DDL dumps (pg_dump output, or hand-written multi-schema DDL) almost
    // always lead with one of these per schema. They're semantic no-ops here —
    // schema qualification comes from each CREATE TABLE's own dotted name — but
    // parseStatements() fails the *entire* batch on a single unparseable
    // statement, so they have to be stripped before parsing rather than just
    // skipped afterward like other non-CREATE-TABLE statements are.
    private static final Pattern CREATE_SCHEMA = Pattern.compile(
            "CREATE\\s+SCHEMA\\s+(IF\\s+NOT\\s+EXISTS\\s+)?[\\w\"]+"
                    + "(\\s+AUTHORIZATION\\s+[\\w\"]+)?\\s*;",
            Pattern.CASE_INSENSITIVE);

    public List<PipeDefinition> inspect(String targetDatabase, String ddl) throws Exception {
        String cleaned = CREATE_SCHEMA.matcher(ddl).replaceAll("");
        Statements stmts = CCJSqlParserUtil.parseStatements(cleaned.trim().endsWith(";")
                ? cleaned : cleaned + ";");

        Set<String> tables = new LinkedHashSet<>();
        Map<String, List<PipeBuilder.RawColumn>> colsByTable  = new LinkedHashMap<>();
        Map<String, Set<String>>                 pksByTable   = new HashMap<>();
        Map<String, Set<String>>                 uniqsByTable = new HashMap<>();
        List<PipeBuilder.FkEdge>                 fks          = new ArrayList<>();
        Map<String, Map<String, List<String>>>   enumsByTable = new HashMap<>();

        for (Statement stmt : stmts.getStatements()) {
            if (!(stmt instanceof CreateTable ct)) continue;
            processTable(ct, tables, colsByTable, pksByTable, uniqsByTable, fks, enumsByTable);
        }

        return PipeBuilder.buildPipes(tables, colsByTable, pksByTable, uniqsByTable,
                fks, enumsByTable, targetDatabase);
    }

    private void processTable(CreateTable ct,
                              Set<String> tables,
                              Map<String, List<PipeBuilder.RawColumn>> colsByTable,
                              Map<String, Set<String>> pksByTable,
                              Map<String, Set<String>> uniqsByTable,
                              List<PipeBuilder.FkEdge> fks,
                              Map<String, Map<String, List<String>>> enumsByTable) {

        String rawSchema = ct.getTable().getSchemaName();
        String schema    = rawSchema != null ? rawSchema.toLowerCase() : DEFAULT_SCHEMA;
        String fullName  = schema + "." + ct.getTable().getName().toLowerCase();
        tables.add(fullName);

        Set<String> tablePks   = new HashSet<>();
        Set<String> tableUniqs = new HashSet<>();

        List<PipeBuilder.RawColumn> rawCols = new ArrayList<>();
        if (ct.getColumnDefinitions() != null) {
            for (ColumnDefinition col : ct.getColumnDefinitions()) {
                rawCols.add(parseColumn(col, fullName, schema, tablePks, tableUniqs, fks, enumsByTable));
            }
        }
        colsByTable.put(fullName, rawCols);

        if (ct.getIndexes() != null) {
            for (Index idx : ct.getIndexes()) {
                parseIndex(idx, fullName, schema, tablePks, tableUniqs, fks, enumsByTable);
            }
        }

        pksByTable.put(fullName, tablePks);
        uniqsByTable.put(fullName, tableUniqs);
    }

    private PipeBuilder.RawColumn parseColumn(ColumnDefinition col,
                                              String fullTableName, String defaultSchema,
                                              Set<String> tablePks, Set<String> tableUniqs,
                                              List<PipeBuilder.FkEdge> fks,
                                              Map<String, Map<String, List<String>>> enumsByTable) {
        String colName = col.getColumnName().toLowerCase();
        var    cdt     = col.getColDataType();
        String rawType = cdt.getDataType().toLowerCase();

        // Array columns: jsqlparser represents "text[]" as dataType="text" plus
        // a separate non-empty getArrayData() (array dimensions), not as a "[]"
        // suffix on the type name itself — the previous check for a literal
        // "[]"/"_"-prefixed type name never matched real parsed output, so
        // every array column silently fell through to a generic string type.
        boolean isArray = (cdt.getArrayData() != null && !cdt.getArrayData().isEmpty())
                         || rawType.endsWith("[]") || rawType.startsWith("_");
        String normType  = isArray ? "ARRAY" : normalizeType(rawType);
        String udtName   = normType;

        List<String> args = cdt.getArgumentsStringList();
        Integer charMaxLen   = null;
        Integer numericPrec  = null;
        Integer numericScale = null;

        if (args != null && !args.isEmpty()) {
            if (isCharType(normType)) {
                charMaxLen = parseIntSafe(args.get(0));
            } else if (PipeBuilder.isNumericType(normType)) {
                numericPrec  = parseIntSafe(args.get(0));
                if (args.size() > 1) numericScale = parseIntSafe(args.get(1));
            }
        }

        String specsJoined = col.getColumnSpecs() != null
                ? String.join(" ", col.getColumnSpecs()) : "";
        String specsUp = specsJoined.toUpperCase();

        boolean isSerial  = rawType.equals("serial") || rawType.equals("bigserial")
                         || rawType.equals("smallserial") || rawType.equals("serial2")
                         || rawType.equals("serial4") || rawType.equals("serial8");
        boolean hasNextval = specsJoined.toLowerCase().contains("nextval(");
        String  colDefault = (isSerial || hasNextval) ? "nextval()" : null;

        boolean isNullable = !specsUp.contains("NOT NULL");

        if (specsUp.contains("PRIMARY KEY")) tablePks.add(colName);
        if (specsUp.contains("UNIQUE") && !specsUp.contains("PRIMARY KEY")) tableUniqs.add(colName);

        extractInlineRef(specsJoined, colName, fullTableName, defaultSchema, fks);
        extractInlineCheck(specsJoined, colName, fullTableName, enumsByTable);

        // Normalize serial types to their underlying integer type
        String finalType = switch (rawType) {
            case "serial", "serial4" -> "integer";
            case "bigserial", "serial8" -> "bigint";
            case "smallserial", "serial2" -> "smallint";
            default -> isArray ? "ARRAY" : normType;
        };

        return new PipeBuilder.RawColumn(colName, finalType, udtName,
                colDefault, charMaxLen, numericPrec, numericScale, isNullable);
    }

    private void parseIndex(Index idx, String fullTableName, String defaultSchema,
                            Set<String> tablePks, Set<String> tableUniqs,
                            List<PipeBuilder.FkEdge> fks,
                            Map<String, Map<String, List<String>>> enumsByTable) {
        String type = idx.getType().toUpperCase().trim();

        if (type.equals("PRIMARY KEY")) {
            if (idx.getColumnsNames() != null)
                idx.getColumnsNames().forEach(c -> tablePks.add(c.toLowerCase()));

        } else if (type.equals("UNIQUE")) {
            List<String> cols = idx.getColumnsNames();
            // Only single-column UNIQUE constraints map to a unique faker type
            if (cols != null && cols.size() == 1)
                tableUniqs.add(cols.get(0).toLowerCase());

        } else if (idx instanceof ForeignKeyIndex fki) {
            List<String> childCols = fki.getColumnsNames();
            List<String> parentCols = fki.getReferencedColumnNames();
            if (childCols != null && !childCols.isEmpty()) {
                String childCol  = childCols.get(0).toLowerCase();
                String parentCol = (parentCols != null && !parentCols.isEmpty())
                        ? parentCols.get(0).toLowerCase() : "id";
                String parentTableName = fki.getTable().getName();
                String parentSchema    = fki.getTable().getSchemaName();
                String qualParent = (parentSchema != null ? parentSchema.toLowerCase() : defaultSchema)
                        + "." + parentTableName.toLowerCase();
                fks.add(new PipeBuilder.FkEdge(fullTableName, childCol, qualParent, parentCol));
            }

        } else if (type.startsWith("CHECK")) {
            extractInlineCheck(idx.toString(), null, fullTableName, enumsByTable);
        }
    }

    private static void extractInlineRef(String specs, String colName, String fullTableName,
                                         String defaultSchema, List<PipeBuilder.FkEdge> fks) {
        Matcher m = INLINE_REF.matcher(specs);
        if (!m.find()) return;
        String ref       = m.group(1);
        String parentCol = m.group(2) != null ? m.group(2).toLowerCase() : "id";
        String qualParent;
        if (ref.contains(".")) {
            String[] parts = ref.split("\\.", 2);
            qualParent = parts[0].toLowerCase() + "." + parts[1].toLowerCase();
        } else {
            qualParent = defaultSchema + "." + ref.toLowerCase();
        }
        fks.add(new PipeBuilder.FkEdge(fullTableName, colName, qualParent, parentCol));
    }

    private static void extractInlineCheck(String text, String colName, String fullTableName,
                                           Map<String, Map<String, List<String>>> enumsByTable) {
        // Extract the content inside CHECK(...)
        Matcher checkM = INLINE_CHECK.matcher(text.trim());
        String expr = checkM.find() ? checkM.group(1).trim() : text;

        Matcher inM = ENUM_IN.matcher(expr);
        if (inM.find()) {
            String col  = colName != null ? colName : inM.group(1).toLowerCase();
            List<String> vals = new ArrayList<>();
            Matcher vm  = ENUM_VAL.matcher(inM.group(2));
            while (vm.find()) vals.add(vm.group(1));
            if (!vals.isEmpty()) {
                enumsByTable.computeIfAbsent(fullTableName, t -> new HashMap<>()).put(col, vals);
            }
        }
    }

    // ── type normalisation ────────────────────────────────────────────────────

    private static String normalizeType(String raw) {
        return switch (raw) {
            case "int", "int4", "integer"           -> "integer";
            case "int8", "bigint"                   -> "bigint";
            case "int2", "smallint"                 -> "smallint";
            case "bool", "boolean"                  -> "boolean";
            case "varchar", "character varying",
                 "nvarchar", "varying"              -> "character varying";
            case "char", "bpchar", "character",
                 "nchar"                            -> "character";
            case "text", "tinytext", "mediumtext",
                 "longtext", "clob"                 -> "text";
            case "uuid"                             -> "uuid";
            case "date"                             -> "date";
            case "timestamp", "datetime",
                 "timestamp without time zone"      -> "timestamp without time zone";
            case "timestamptz",
                 "timestamp with time zone"         -> "timestamp with time zone";
            case "time", "time without time zone"   -> "time";
            case "numeric", "decimal",
                 "number"                           -> "numeric";
            case "real", "float4"                   -> "real";
            case "float8", "double",
                 "double precision", "float"        -> "double precision";
            case "money"                            -> "money";
            case "jsonb"                            -> "jsonb";
            case "json"                             -> "json";
            case "inet"                             -> "inet";
            case "cidr"                             -> "cidr";
            default                                 -> raw;
        };
    }

    private static boolean isCharType(String t) {
        return t.equals("character varying") || t.equals("character") || t.equals("text");
    }

    private static Integer parseIntSafe(String s) {
        try { return Integer.parseInt(s.trim()); } catch (NumberFormatException e) { return null; }
    }
}
