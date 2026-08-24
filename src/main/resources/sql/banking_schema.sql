DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    id            INTEGER        PRIMARY KEY,
    first_name    VARCHAR(100)   NOT NULL,
    last_name     VARCHAR(100)   NOT NULL,
    email         VARCHAR(255)   NOT NULL,
    phone         VARCHAR(30)    NOT NULL,
    created_date  DATE           NOT NULL,
    status        VARCHAR(20)    NOT NULL CHECK (status IN ('active', 'inactive', 'suspended'))
);

CREATE TABLE accounts (
    id            INTEGER        PRIMARY KEY,
    customer_id   INTEGER        NOT NULL REFERENCES customers(id),
    account_type  VARCHAR(20)    NOT NULL CHECK (account_type IN ('checking', 'savings', 'money_market', 'cd')),
    status        VARCHAR(20)    NOT NULL CHECK (status IN ('active', 'closed', 'frozen')),
    balance       NUMERIC(12,2)  NOT NULL,
    opened_date   DATE           NOT NULL
);

CREATE TABLE transactions (
    id                INTEGER        PRIMARY KEY,
    account_id        INTEGER        NOT NULL REFERENCES accounts(id),
    transaction_type  VARCHAR(10)    NOT NULL CHECK (transaction_type IN ('credit', 'debit')),
    amount            NUMERIC(12,2)  NOT NULL,
    transaction_date  DATE           NOT NULL,
    description       VARCHAR(255),
    status            VARCHAR(20)    NOT NULL CHECK (status IN ('pending', 'settled', 'reversed', 'failed'))
);
