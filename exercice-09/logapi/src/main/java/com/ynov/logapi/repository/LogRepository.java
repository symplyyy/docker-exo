package com.ynov.logapi.repository;

import com.ynov.logapi.model.Log;
import org.springframework.data.jpa.repository.JpaRepository;

public interface LogRepository extends JpaRepository<Log, Long> {
}
