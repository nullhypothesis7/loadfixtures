package com.testfixtures.metrics;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import java.util.List;

public class RunMetrics {

    private final MeterRegistry registry;

    public RunMetrics(MeterRegistry registry) {
        this.registry = registry;
        for (String status : List.of("QUEUED", "RUNNING", "DONE", "FAILED")) {
            Counter.builder("testfixtures.run.status")
                    .tag("status", status)
                    .register(registry);
        }
    }

    public void increment(String status) {
        Counter.builder("testfixtures.run.status")
                .tag("status", status)
                .register(registry)
                .increment();
    }
}
