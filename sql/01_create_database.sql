-- Create the project's owner role and the database.
CREATE ROLE football_admin
    LOGIN;

CREATE DATABASE football_predictor
    OWNER football_admin;