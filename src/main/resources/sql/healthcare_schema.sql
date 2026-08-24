DROP TABLE IF EXISTS encounters;
DROP TABLE IF EXISTS providers;
DROP TABLE IF EXISTS patients;

CREATE TABLE patients (
    id             INTEGER      PRIMARY KEY,
    first_name     VARCHAR(100) NOT NULL,
    last_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(255) NOT NULL,
    phone          VARCHAR(30)  NOT NULL,
    date_of_birth  DATE         NOT NULL,
    gender         VARCHAR(30)  NOT NULL CHECK (gender IN ('male', 'female', 'non_binary', 'prefer_not_to_say')),
    status         VARCHAR(20)  NOT NULL CHECK (status IN ('active', 'inactive', 'deceased'))
);

CREATE TABLE providers (
    id              INTEGER      PRIMARY KEY,
    first_name      VARCHAR(100) NOT NULL,
    last_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    specialty       VARCHAR(50)  NOT NULL,
    license_number  VARCHAR(36)  NOT NULL,
    status          VARCHAR(20)  NOT NULL CHECK (status IN ('active', 'inactive', 'on_leave'))
);

CREATE TABLE encounters (
    id              INTEGER      PRIMARY KEY,
    patient_id      INTEGER      NOT NULL REFERENCES patients(id),
    provider_id     INTEGER      NOT NULL REFERENCES providers(id),
    encounter_date  DATE         NOT NULL,
    encounter_type  VARCHAR(20)  NOT NULL CHECK (encounter_type IN ('inpatient', 'outpatient', 'emergency', 'telehealth')),
    diagnosis_code  VARCHAR(10),
    status          VARCHAR(20)  NOT NULL CHECK (status IN ('scheduled', 'completed', 'cancelled', 'no_show'))
);
