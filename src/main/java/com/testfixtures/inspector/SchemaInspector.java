package com.testfixtures.inspector;

import com.testfixtures.model.PipeDefinition;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

public class SchemaInspector {

    private final DataSource dataSource;

    public SchemaInspector(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /** Backward-compatible: inspect only the public schema. */
    public List<PipeDefinition> inspect(String targetDatabase) throws SQLException {
        return inspect(targetDatabase, List.of("public"));
    }

    /**
     * Inspect one or more named schemas, topologically sort by FK dependency,
     * and return a PipeDefinition per table in insert-safe order.
     */
    public List<PipeDefinition> inspect(String targetDatabase, List<String> schemas) throws SQLException {
        List<String> effective = (schemas == null || schemas.isEmpty()) ? List.of("public") : schemas;
        String schemaList = toSqlList(effective);

        try (Connection conn = dataSource.getConnection()) {
            Set<String>                            tables     = loadTables(conn, schemaList);
            Map<String, List<PipeBuilder.RawColumn>>  cols    = loadColumns(conn, schemaList);
            Map<String, Set<String>>               pks        = loadPrimaryKeys(conn, schemaList);
            Map<String, Set<String>>               uniques    = loadUniqueColumns(conn, schemaList);
            List<PipeBuilder.FkEdge>               fks        = loadForeignKeys(conn, schemaList);
            Map<String, Map<String, List<String>>> checkEnums = loadCheckEnums(conn, schemaList);

            return PipeBuilder.buildPipes(tables, cols, pks, uniques, fks, checkEnums, targetDatabase);
        }
    }

    // ── information_schema queries ────────────────────────────────────────────

    /** Returns schema-qualified table keys: "schema.table" */
    private Set<String> loadTables(Connection conn, String schemaList) throws SQLException {
        Set<String> tables = new LinkedHashSet<>();
        String sql = """
                SELECT table_schema, table_name
                FROM information_schema.tables
                WHERE table_schema IN (%s) AND table_type = 'BASE TABLE'
                ORDER BY table_schema, table_name
                """.formatted(schemaList);
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                tables.add(rs.getString("table_schema") + "." + rs.getString("table_name"));
            }
        }
        return tables;
    }

    /** Returns map keyed by "schema.table". */
    private Map<String, List<PipeBuilder.RawColumn>> loadColumns(Connection conn, String schemaList) throws SQLException {
        Map<String, List<PipeBuilder.RawColumn>> result = new LinkedHashMap<>();
        String sql = """
                SELECT table_schema, table_name, column_name, data_type, udt_name,
                       is_nullable, column_default, character_maximum_length,
                       numeric_precision, numeric_scale
                FROM information_schema.columns
                WHERE table_schema IN (%s)
                ORDER BY table_schema, table_name, ordinal_position
                """.formatted(schemaList);
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key = rs.getString("table_schema") + "." + rs.getString("table_name");

                int maxLen = rs.getInt("character_maximum_length");
                Integer charMaxLen = rs.wasNull() ? null : maxLen;

                int numPrec = rs.getInt("numeric_precision");
                Integer numericPrecision = rs.wasNull() ? null : numPrec;

                int numScale = rs.getInt("numeric_scale");
                Integer numericScale = rs.wasNull() ? null : numScale;

                result.computeIfAbsent(key, t -> new ArrayList<>())
                      .add(new PipeBuilder.RawColumn(
                              rs.getString("column_name"),
                              rs.getString("data_type"),
                              rs.getString("udt_name"),
                              rs.getString("column_default"),
                              charMaxLen,
                              numericPrecision,
                              numericScale,
                              "YES".equals(rs.getString("is_nullable"))));
            }
        }
        return result;
    }

    /** Returns map keyed by "schema.table" → set of PK column names. */
    private Map<String, Set<String>> loadPrimaryKeys(Connection conn, String schemaList) throws SQLException {
        Map<String, Set<String>> result = new HashMap<>();
        String sql = """
                SELECT tc.table_schema, tc.table_name, kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                  ON tc.constraint_name = kcu.constraint_name
                 AND tc.table_schema    = kcu.table_schema
                WHERE tc.table_schema IN (%s) AND tc.constraint_type = 'PRIMARY KEY'
                """.formatted(schemaList);
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key = rs.getString("table_schema") + "." + rs.getString("table_name");
                result.computeIfAbsent(key, t -> new HashSet<>())
                      .add(rs.getString("column_name"));
            }
        }
        return result;
    }

    /**
     * Returns single-column UNIQUE constraints (excluding PKs), keyed by "schema.table".
     * Composite unique constraints are not included — they're too complex to handle generically.
     */
    private Map<String, Set<String>> loadUniqueColumns(Connection conn, String schemaList) throws SQLException {
        Map<String, Set<String>> result = new HashMap<>();
        String sql = """
                WITH single_col AS (
                    SELECT tc.table_schema, tc.table_name, tc.constraint_name
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.key_column_usage kcu
                      ON tc.constraint_name = kcu.constraint_name
                     AND tc.table_schema    = kcu.table_schema
                    WHERE tc.table_schema IN (%s) AND tc.constraint_type = 'UNIQUE'
                    GROUP BY tc.table_schema, tc.table_name, tc.constraint_name
                    HAVING COUNT(*) = 1
                )
                SELECT s.table_schema, s.table_name, kcu.column_name
                FROM single_col s
                JOIN information_schema.key_column_usage kcu
                  ON kcu.constraint_name = s.constraint_name
                 AND kcu.table_schema    = s.table_schema
                """.formatted(schemaList);
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key = rs.getString("table_schema") + "." + rs.getString("table_name");
                result.computeIfAbsent(key, t -> new HashSet<>())
                      .add(rs.getString("column_name"));
            }
        }
        return result;
    }

    /**
     * Parses CHECK constraints using pg_get_constraintdef — necessary because
     * information_schema.check_constraints only surfaces NOT NULL checks, not
     * IN-list enums.  Handles both VARCHAR (::character varying) and CHAR
     * (::bpchar) column types.
     *
     * Returns map keyed by "schema.table" → column → [allowed values].
     */
    private Map<String, Map<String, List<String>>> loadCheckEnums(
            Connection conn, String schemaList) throws SQLException {

        Map<String, Map<String, List<String>>> result = new HashMap<>();

        String sql = """
                SELECT n.nspname, c.relname, pg_get_constraintdef(con.oid)
                FROM pg_constraint con
                JOIN pg_class     c   ON c.oid   = con.conrelid
                JOIN pg_namespace n   ON n.oid   = c.relnamespace
                WHERE con.contype = 'c'
                  AND n.nspname   IN (%s)
                """.formatted(schemaList);

        // VARCHAR: ((col)::text = ANY ((ARRAY['V'::character varying, ...])::text[]))
        Pattern varcharCol = Pattern.compile("\\(\\((\\w+)\\)::text\\s*=\\s*ANY");
        Pattern varcharVal = Pattern.compile("'([^']+)'::character varying");

        // CHAR:    (col = ANY (ARRAY['I'::bpchar, ...]))
        Pattern bpcharCol  = Pattern.compile("CHECK\\s*\\(\\(?\\s*(\\w+)\\s*=\\s*ANY");
        Pattern bpcharVal  = Pattern.compile("'([^']+)'::bpchar");

        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                String key    = rs.getString(1) + "." + rs.getString(2);
                String clause = rs.getString(3);

                Matcher cm = varcharCol.matcher(clause);
                if (cm.find()) {
                    String col = cm.group(1);
                    List<String> vals = new ArrayList<>();
                    Matcher vm = varcharVal.matcher(clause);
                    while (vm.find()) vals.add(vm.group(1));
                    if (!vals.isEmpty()) {
                        result.computeIfAbsent(key, t -> new HashMap<>()).put(col, vals);
                        continue;
                    }
                }

                Matcher bcm = bpcharCol.matcher(clause);
                if (bcm.find()) {
                    String col = bcm.group(1);
                    List<String> vals = new ArrayList<>();
                    Matcher vm = bpcharVal.matcher(clause);
                    while (vm.find()) vals.add(vm.group(1));
                    if (!vals.isEmpty()) {
                        result.computeIfAbsent(key, t -> new HashMap<>()).put(col, vals);
                    }
                }
            }
        }
        return result;
    }

    /**
     * Loads FK edges across all requested schemas.  Child and parent table names
     * are both schema-qualified ("schema.table") so the topological sort can
     * handle cross-schema dependencies (e.g. party.party → ref.country).
     */
    private List<PipeBuilder.FkEdge> loadForeignKeys(Connection conn, String schemaList) throws SQLException {
        List<PipeBuilder.FkEdge> result = new ArrayList<>();
        String sql = """
                SELECT DISTINCT
                    kcu.table_schema  || '.' || kcu.table_name  AS child,
                    kcu.column_name                              AS child_col,
                    ccu.table_schema  || '.' || ccu.table_name  AS parent,
                    ccu.column_name                              AS parent_col
                FROM information_schema.referential_constraints rc
                JOIN information_schema.key_column_usage kcu
                  ON kcu.constraint_name   = rc.constraint_name
                 AND kcu.constraint_schema = rc.constraint_schema
                JOIN information_schema.constraint_column_usage ccu
                  ON ccu.constraint_name   = rc.unique_constraint_name
                 AND ccu.constraint_schema = rc.unique_constraint_schema
                WHERE kcu.table_schema IN (%s)
                """.formatted(schemaList);
        try (PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                result.add(new PipeBuilder.FkEdge(
                        rs.getString("child"),
                        rs.getString("child_col"),
                        rs.getString("parent"),
                        rs.getString("parent_col")));
            }
        }
        return result;
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private static String toSqlList(List<String> schemas) {
        return schemas.stream()
                .map(s -> "'" + s.replace("'", "''") + "'")
                .collect(Collectors.joining(", "));
    }
}
