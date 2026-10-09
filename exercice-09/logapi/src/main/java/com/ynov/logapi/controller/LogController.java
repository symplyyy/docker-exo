package com.ynov.logapi.controller;

import com.ynov.logapi.model.Log;
import com.ynov.logapi.repository.LogRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1/logs")
public class LogController {

    private final LogRepository logRepository;

    public LogController(LogRepository logRepository) {
        this.logRepository = logRepository;
    }

    @GetMapping
    public List<Log> getAllLogs() {
        return logRepository.findAll();
    }

    @PostMapping
    public ResponseEntity<Log> addLog(@RequestBody Log log) {
        log.setId(null);
        Log saved = logRepository.save(log);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }
}
