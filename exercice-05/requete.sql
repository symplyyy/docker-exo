CREATE TABLE eleves (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(50),
    prenom VARCHAR(50)
);

INSERT INTO eleves (nom, prenom) VALUES ('Dupont', 'Lucas'), ('Martin', 'Emma'), ('Bernard', 'Hugo');
