package com.testfixtures.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class Run {

    private String id;
    private String pipeName;
    private String status;
    private Instant createdAt;
}
