package com.ynov.crudapi.repository;

import com.ynov.crudapi.model.Dog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DogRepository extends JpaRepository<Dog, Long> {
}
