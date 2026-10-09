package com.ynov.dogapi.controller;

import com.ynov.dogapi.model.Dog;
import com.ynov.dogapi.repository.DogRepository;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Optional;

@RestController
@RequestMapping("/api/v1/dogs")
public class DogController {

    private final DogRepository dogRepository;

    public DogController(DogRepository dogRepository) {
        this.dogRepository = dogRepository;
    }

    @GetMapping
    public List<Dog> getAllDogs() {
        return dogRepository.findAll();
    }

    @GetMapping("/{dogId}")
    public ResponseEntity<Dog> getDog(@PathVariable Long dogId) {
        Optional<Dog> dog = dogRepository.findById(dogId);
        if (dog.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(dog.get());
    }

    @PostMapping
    public ResponseEntity<Dog> createDog(@RequestBody Dog dog) {
        dog.setId(null);
        Dog saved = dogRepository.save(dog);
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{dogId}")
    public ResponseEntity<Dog> updateDog(@PathVariable Long dogId, @RequestBody Dog newDog) {
        Optional<Dog> optionalDog = dogRepository.findById(dogId);
        if (optionalDog.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        Dog dog = optionalDog.get();
        dog.setName(newDog.getName());
        dog.setBirthDate(newDog.getBirthDate());
        dog.setBreed(newDog.getBreed());
        dog.setSterilized(newDog.isSterilized());
        return ResponseEntity.ok(dogRepository.save(dog));
    }

    @DeleteMapping("/{dogId}")
    public ResponseEntity<Void> deleteDog(@PathVariable Long dogId) {
        if (!dogRepository.existsById(dogId)) {
            return ResponseEntity.notFound().build();
        }
        dogRepository.deleteById(dogId);
        return ResponseEntity.noContent().build();
    }
}
