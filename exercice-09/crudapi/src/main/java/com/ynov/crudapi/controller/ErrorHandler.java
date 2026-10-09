package com.ynov.crudapi.controller;

import com.ynov.crudapi.service.LogService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public class ErrorHandler {

    private final LogService logService;

    public ErrorHandler(LogService logService) {
        this.logService = logService;
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<String> badRequest(Exception e, HttpServletRequest request) {
        logService.warn(e.getMessage(), request.getMethod(), request.getRequestURI());
        return ResponseEntity.badRequest().body("Requete invalide");
    }

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<String> serverError(RuntimeException e, HttpServletRequest request) {
        logService.error(e.getMessage(), request.getMethod(), request.getRequestURI());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Erreur serveur");
    }
}
