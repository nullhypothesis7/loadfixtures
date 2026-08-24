package com.testfixtures.sink;

import com.testfixtures.model.PipeDefinition;

import java.util.List;
import java.util.Map;

public interface DataSink {
    /** @return the number of rows actually persisted — not necessarily rows.size();
     *  a sink backed by ON CONFLICT DO NOTHING (or similar) may silently skip some. */
    int write(List<Map<String, Object>> rows, PipeDefinition pipe) throws Exception;
}
