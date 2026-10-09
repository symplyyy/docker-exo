package com.ynov.crudapi.service;

import com.ynov.crudapi.model.Log;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.time.LocalDateTime;

@Service
public class LogService {

    private final RestTemplate restTemplate = new RestTemplate();

    @Value("${log.api.url}")
    private String logApiUrl;

    public void sendLog(String level, String message, String method, String path) {
        Log log = new Log(message, "[CrudAPI] " + method + " " + path, LocalDateTime.now().toString(), level);
        try {
            restTemplate.postForObject(logApiUrl, log, Log.class);
        } catch (Exception e) {
            System.out.println("Impossible d'envoyer le log : " + e.getMessage());
        }
    }

    public void info(String message, String method, String path) {
        sendLog("INFO", message, method, path);
    }

    public void warn(String message, String method, String path) {
        sendLog("WARN", message, method, path);
    }

    public void error(String message, String method, String path) {
        sendLog("ERR", message, method, path);
    }
}
