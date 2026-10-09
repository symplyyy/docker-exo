CREATE DATABASE IF NOT EXISTS kennelDB;
USE kennelDB;

CREATE TABLE clients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(50) NOT NULL,
    prenom VARCHAR(50) NOT NULL,
    date_naissance DATE,
    pseudo VARCHAR(50) UNIQUE
);

CREATE TABLE adresses (
    id INT AUTO_INCREMENT PRIMARY KEY,
    numero VARCHAR(10),
    rue VARCHAR(100) NOT NULL,
    code_postal VARCHAR(5) NOT NULL,
    commune VARCHAR(50) NOT NULL
);

CREATE TABLE clients_adresses (
    client_id INT,
    adresse_id INT,
    PRIMARY KEY (client_id, adresse_id),
    FOREIGN KEY (client_id) REFERENCES clients(id),
    FOREIGN KEY (adresse_id) REFERENCES adresses(id)
);

CREATE TABLE chiens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(50) NOT NULL,
    date_naissance DATE,
    race VARCHAR(50),
    sterilise BOOLEAN DEFAULT FALSE,
    client_id INT,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

CREATE TABLE chats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nom VARCHAR(50) NOT NULL,
    date_naissance DATE,
    race VARCHAR(50),
    sterilise BOOLEAN DEFAULT FALSE,
    client_id INT,
    FOREIGN KEY (client_id) REFERENCES clients(id)
);

INSERT INTO clients (nom, prenom, date_naissance, pseudo) VALUES
('Dupont', 'Lucas', '1995-04-12', 'lucasd'),
('Martin', 'Emma', '1988-11-03', 'emma88'),
('Bernard', 'Hugo', '2001-07-25', 'hugob'),
('Petit', 'Lea', '1999-02-14', 'leap');

INSERT INTO adresses (numero, rue, code_postal, commune) VALUES
('12', 'rue de la Paix', '75002', 'Paris'),
('5', 'avenue Jean Jaures', '69007', 'Lyon'),
('28', 'boulevard Victor Hugo', '33000', 'Bordeaux');

INSERT INTO clients_adresses (client_id, adresse_id) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 1);

INSERT INTO chiens (nom, date_naissance, race, sterilise, client_id) VALUES
('Rex', '2018-05-10', 'Berger Allemand', TRUE, 1),
('Pepito', '2021-09-01', 'Chihuahua', FALSE, 2),
('Oslo', '2020-03-15', 'Golden Retriever', TRUE, 3);

INSERT INTO chats (nom, date_naissance, race, sterilise, client_id) VALUES
('Mimi', '2019-06-20', 'Siamois', TRUE, 2),
('Felix', '2022-01-08', 'Europeen', FALSE, 4),
('Tigrou', '2017-12-24', 'Maine Coon', TRUE, 1);
