package com.ynov.dogapi.repository;

import com.ynov.dogapi.model.Dog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DogRepository extends JpaRepository<Dog, Long> {
}
