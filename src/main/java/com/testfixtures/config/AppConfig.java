package com.testfixtures.config;

import lombok.Data;

import java.util.HashMap;
import java.util.Map;

@Data
public class AppConfig {

    private String jdbcUrl;
    private String username;
    private String password;
    private String pipesDirectory;
    private String redisUrl;
    private int workerPoolSize;
    private Map<String, String> databaseUrls;
    private Map<String, String> databaseUsers;
    private Map<String, String> databasePasswords;
    private String csvOutputDir;
    private String parquetOutputDir;
    private String kafkaBootstrapServers;
    private String schemaRegistryUrl;

    public static AppConfig fromEnv() {
        AppConfig config = new AppConfig();
        config.setJdbcUrl(System.getenv("DB_URL"));
        config.setUsername(System.getenv("DB_USER"));
        config.setPassword(System.getenv("DB_PASSWORD"));
        String pipesDir = System.getenv("PIPES_DIR");
        config.setPipesDirectory(pipesDir != null ? pipesDir : "src/main/resources/pipes");
        String redisUrl = System.getenv("REDIS_URL");
        config.setRedisUrl(redisUrl != null ? redisUrl : "redis://localhost:6379");
        String poolSize = System.getenv("WORKER_POOL_SIZE");
        config.setWorkerPoolSize(poolSize != null ? Integer.parseInt(poolSize) : 10);
        config.setDatabaseUrls(loadPrefixedEnv("DB_URL_"));
        config.setDatabaseUsers(loadPrefixedEnv("DB_USER_"));
        config.setDatabasePasswords(loadPrefixedEnv("DB_PASS_"));
        String csvDir = System.getenv("CSV_OUTPUT_DIR");
        config.setCsvOutputDir(csvDir != null ? csvDir : "./csv-output");
        String parquetDir = System.getenv("PARQUET_OUTPUT_DIR");
        config.setParquetOutputDir(parquetDir != null ? parquetDir : "./parquet-output");
        String kafkaBootstrap = System.getenv("KAFKA_BOOTSTRAP_SERVERS");
        config.setKafkaBootstrapServers(kafkaBootstrap != null ? kafkaBootstrap : "localhost:9092");
        String schemaRegistry = System.getenv("SCHEMA_REGISTRY_URL");
        config.setSchemaRegistryUrl(schemaRegistry != null ? schemaRegistry : "http://localhost:8081");
        return config;
    }

    private static Map<String, String> loadPrefixedEnv(String prefix) {
        Map<String, String> map = new HashMap<>();
        System.getenv().forEach((key, value) -> {
            if (key.startsWith(prefix)) {
                map.put(key.substring(prefix.length()).toLowerCase(), value);
            }
        });
        return map;
    }
}
