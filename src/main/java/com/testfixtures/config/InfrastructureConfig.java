package com.testfixtures.config;

import com.testfixtures.metrics.RunMetrics;
import com.testfixtures.queue.RedisQueue;
import com.testfixtures.repository.RunRepository;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class InfrastructureConfig {

    @Bean
    public AppConfig appConfig() {
        return AppConfig.fromEnv();
    }

    @Bean(destroyMethod = "close")
    public RedisQueue redisQueue(AppConfig appConfig) {
        return new RedisQueue(appConfig.getRedisUrl());
    }

    @Bean
    public RunRepository runRepository() {
        return new RunRepository();
    }

    @Bean
    public RunMetrics runMetrics(MeterRegistry registry) {
        return new RunMetrics(registry);
    }
}
