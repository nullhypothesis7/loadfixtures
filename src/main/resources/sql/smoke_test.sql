DROP TABLE IF EXISTS smoke_users;

CREATE TABLE smoke_users (
    id           INTEGER      PRIMARY KEY,
    first_name   VARCHAR(100) NOT NULL,
    last_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(255) NOT NULL,
    created_date DATE         NOT NULL,
    status       VARCHAR(20)  NOT NULL CHECK (status IN ('active', 'inactive', 'pending'))
);
