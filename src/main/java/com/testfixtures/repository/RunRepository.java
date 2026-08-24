package com.testfixtures.repository;

import com.testfixtures.model.Run;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

public class RunRepository {

    private final ConcurrentHashMap<String, Run> store = new ConcurrentHashMap<>();

    public void save(Run run) {
        store.put(run.getId(), run);
    }

    public Optional<Run> findById(String id) {
        return Optional.ofNullable(store.get(id));
    }

    public void updateStatus(String id, String status) {
        Run run = store.get(id);
        if (run != null) {
            run.setStatus(status);
        }
    }
}
