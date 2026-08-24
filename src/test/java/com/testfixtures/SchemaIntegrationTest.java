package com.testfixtures;

import com.testfixtures.inspector.SchemaInspector;
import com.testfixtures.loader.RowGenerator;
import com.testfixtures.model.PipeDefinition;
import com.testfixtures.sink.JdbcSink;
import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.testcontainers.containers.PostgreSQLContainer;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Validates the full tool pipeline against each real schema in the repo.
 *
 * For each schema: spins up a fresh Postgres container, loads the actual SQL,
 * runs SchemaInspector → RowGenerator → JdbcSink, then asserts:
 *   1. Every table received rows (no silent total failures)
 *   2. Zero orphaned FK references across every FK relationship in the schema
 *      (proves topo-sort inserted parents before children)
 *
 * This is the validation gate for any schema entering the pipeline.
 * Add a new Arguments entry here when a new schema is introduced.
 */
class SchemaIntegrationTest {

    static Stream<Arguments> schemas() {
        return Stream.of(
            Arguments.of("banking",    "sql/banking_schema.sql",   List.of("public")),
            Arguments.of("healthcare", "sql/healthcare_schema.sql", List.of("public")),
            Arguments.of("pgbank",     "sql/bank_schema.sql",
                List.of("ref", "audit", "party", "account", "txn",
                        "lending", "card", "compliance", "ops", "wart")),
            Arguments.of("salesforce", "sql/salesforce_schema.sql", List.of("salesforce")),
            Arguments.of("salesforce_enterprise", "sql/salesforce_enterprise_schema.sql",
                List.of("sf_core", "sf_account", "sf_sales", "sf_service", "sf_field_service",
                        "sf_activity", "sf_content", "sf_collab", "sf_process", "sf_marketing",
                        "sf_platform", "sf_social", "sf_assets", "sf_messaging"))
        );
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("schemas")
    void pipelineInsertsDataWithNoFkViolations(String name, String sqlResource,
                                               List<String> pgSchemas) throws Exception {
        try (PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15")
                .withDatabaseName(name)
                .withUsername("test")
                .withPassword("test")
                .withInitScript(sqlResource)) {

            postgres.start();

            HikariConfig hc = new HikariConfig();
            hc.setJdbcUrl(postgres.getJdbcUrl());
            hc.setUsername(postgres.getUsername());
            hc.setPassword(postgres.getPassword());

            try (HikariDataSource ds = new HikariDataSource(hc)) {

                // Inspect real schema — topo-sorted pipes in parent-first order
                SchemaInspector inspector = new SchemaInspector(ds);
                List<PipeDefinition> pipes = inspector.inspect(name, pgSchemas);
                assertFalse(pipes.isEmpty(), name + ": SchemaInspector returned no pipes");

                // Generate and insert — any FK violation here throws and fails the test
                JdbcSink sink = new JdbcSink(ds);
                for (PipeDefinition pipe : pipes) {
                    List<Map<String, Object>> rows = RowGenerator.generate(pipe);
                    sink.write(rows, pipe);
                }

                try (Connection conn = ds.getConnection()) {

                    // 1. Every table has at least some rows
                    for (PipeDefinition pipe : pipes) {
                        try (Statement st = conn.createStatement();
                             ResultSet rs = st.executeQuery(
                                     "SELECT COUNT(*) FROM " + pipe.getTargetTable())) {
                            rs.next();
                            assertTrue(rs.getInt(1) > 0,
                                    name + ": " + pipe.getTargetTable() + " has 0 rows after insert");
                        }
                    }

                    // 2. Zero orphaned FK references — explicit proof that topo-sort
                    //    inserted every parent table before its dependent children
                    List<String[]> fkRelationships = loadFkRelationships(conn, pgSchemas);
                    for (String[] fk : fkRelationships) {
                        String childTable = fk[0], childCol = fk[1];
                        String parentTable = fk[2], parentCol = fk[3];
                        String orphanSql = String.format(
                                "SELECT COUNT(*) FROM %s c " +
                                "LEFT JOIN %s p ON c.%s = p.%s " +
                                "WHERE c.%s IS NOT NULL AND p.%s IS NULL",
                                childTable, parentTable, childCol, parentCol, childCol, parentCol);
                        try (Statement st = conn.createStatement();
                             ResultSet rs = st.executeQuery(orphanSql)) {
                            rs.next();
                            assertEquals(0, rs.getLong(1),
                                    name + ": orphaned FK — " + childTable + "." + childCol
                                    + " references missing row in " + parentTable);
                        }
                    }
                }
            }
        }
    }

    private List<String[]> loadFkRelationships(Connection conn, List<String> schemas) throws Exception {
        String schemaList = schemas.stream()
                .map(s -> "'" + s + "'")
                .collect(Collectors.joining(", "));
        String sql = """
                SELECT DISTINCT
                    kcu.table_schema || '.' || kcu.table_name  AS child_table,
                    kcu.column_name                             AS child_col,
                    ccu.table_schema || '.' || ccu.table_name  AS parent_table,
                    ccu.column_name                             AS parent_col
                FROM information_schema.referential_constraints rc
                JOIN information_schema.key_column_usage kcu
                  ON kcu.constraint_name   = rc.constraint_name
                 AND kcu.constraint_schema = rc.constraint_schema
                JOIN information_schema.constraint_column_usage ccu
                  ON ccu.constraint_name   = rc.unique_constraint_name
                 AND ccu.constraint_schema = rc.unique_constraint_schema
                WHERE kcu.table_schema IN (%s)
                """.formatted(schemaList);
        List<String[]> result = new ArrayList<>();
        try (Statement st = conn.createStatement(); ResultSet rs = st.executeQuery(sql)) {
            while (rs.next()) {
                result.add(new String[]{
                    rs.getString("child_table"), rs.getString("child_col"),
                    rs.getString("parent_table"), rs.getString("parent_col")
                });
            }
        }
        return result;
    }
}
