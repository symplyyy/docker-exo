package com.ynov.crudapi.controller;

import com.ynov.crudapi.model.Dog;
import com.ynov.crudapi.repository.DogRepository;
import com.ynov.crudapi.service.LogService;
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
    private final LogService logService;

    public DogController(DogRepository dogRepository, LogService logService) {
        this.dogRepository = dogRepository;
        this.logService = logService;
    }

    @GetMapping
    public List<Dog> getAllDogs() {
        List<Dog> dogs = dogRepository.findAll();
        logService.info(dogs.size() + " chien(s) recupere(s)", "GET", "/api/v1/dogs");
        return dogs;
    }

    @GetMapping("/{dogId}")
    public ResponseEntity<Dog> getDog(@PathVariable Long dogId) {
        String path = "/api/v1/dogs/" + dogId;
        Optional<Dog> dog = dogRepository.findById(dogId);
        if (dog.isEmpty()) {
            logService.warn("Chien " + dogId + " introuvable", "GET", path);
            return ResponseEntity.notFound().build();
        }
        logService.info("Chien " + dogId + " recupere", "GET", path);
        return ResponseEntity.ok(dog.get());
    }

    @PostMapping
    public ResponseEntity<Dog> createDog(@RequestBody Dog dog) {
        if (dog.getName() == null || dog.getName().isBlank()) {
            logService.warn("Le nom du chien est obligatoire", "POST", "/api/v1/dogs");
            return ResponseEntity.badRequest().build();
        }
        dog.setId(null);
        Dog saved = dogRepository.save(dog);
        logService.info("Chien " + saved.getId() + " cree", "POST", "/api/v1/dogs");
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }

    @PutMapping("/{dogId}")
    public ResponseEntity<Dog> updateDog(@PathVariable Long dogId, @RequestBody Dog newDog) {
        String path = "/api/v1/dogs/" + dogId;
        Optional<Dog> optionalDog = dogRepository.findById(dogId);
        if (optionalDog.isEmpty()) {
            logService.warn("Chien " + dogId + " introuvable", "PUT", path);
            return ResponseEntity.notFound().build();
        }
        Dog dog = optionalDog.get();
        dog.setName(newDog.getName());
        dog.setBirthDate(newDog.getBirthDate());
        dog.setBreed(newDog.getBreed());
        dog.setSterilized(newDog.isSterilized());
        logService.info("Chien " + dogId + " modifie", "PUT", path);
        return ResponseEntity.ok(dogRepository.save(dog));
    }

    @DeleteMapping("/{dogId}")
    public ResponseEntity<Void> deleteDog(@PathVariable Long dogId) {
        String path = "/api/v1/dogs/" + dogId;
        if (!dogRepository.existsById(dogId)) {
            logService.warn("Chien " + dogId + " introuvable", "DELETE", path);
            return ResponseEntity.notFound().build();
        }
        dogRepository.deleteById(dogId);
        logService.info("Chien " + dogId + " supprime", "DELETE", path);
        return ResponseEntity.noContent().build();
    }
}
