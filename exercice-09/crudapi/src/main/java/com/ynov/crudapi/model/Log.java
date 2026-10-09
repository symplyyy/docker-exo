package com.ynov.crudapi.model;

public class Log {

    private String message;
    private String source;
    private String timestamp;
    private String level;

    public Log() {
    }

    public Log(String message, String source, String timestamp, String level) {
        this.message = message;
        this.source = source;
        this.timestamp = timestamp;
        this.level = level;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public String getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(String timestamp) {
        this.timestamp = timestamp;
    }

    public String getLevel() {
        return level;
    }

    public void setLevel(String level) {
        this.level = level;
    }
}
