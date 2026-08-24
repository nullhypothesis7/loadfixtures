-- =============================================================================
-- BANK SCHEMA — Enterprise Banking Data Model (~88 tables across 10 domains)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS party;
CREATE SCHEMA IF NOT EXISTS account;
CREATE SCHEMA IF NOT EXISTS txn;
CREATE SCHEMA IF NOT EXISTS lending;
CREATE SCHEMA IF NOT EXISTS card;
CREATE SCHEMA IF NOT EXISTS compliance;
CREATE SCHEMA IF NOT EXISTS ops;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS wart;

-- =============================================================================
-- REFERENCE DOMAIN (5 tables) — created first; other schemas reference these
-- =============================================================================

CREATE TABLE ref.country (
    country_code  CHAR(2)      PRIMARY KEY,
    country_name  VARCHAR(100) NOT NULL,
    alpha3        CHAR(3)      NOT NULL,
    numeric_code  CHAR(3),
    region        VARCHAR(50),
    is_sanctioned BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE ref.currency (
    currency_code VARCHAR(3)   PRIMARY KEY,
    currency_name VARCHAR(100) NOT NULL,
    numeric_code  CHAR(3),
    minor_units   SMALLINT     NOT NULL DEFAULT 2,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE ref.reference_codes (
    id          BIGSERIAL    PRIMARY KEY,
    domain      VARCHAR(50)  NOT NULL,
    code        VARCHAR(50)  NOT NULL,
    description VARCHAR(255) NOT NULL,
    sort_order  INTEGER      NOT NULL DEFAULT 0,
    metadata    JSONB,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ,
    UNIQUE (domain, code)
);

CREATE TABLE ref.product_catalog (
    id             BIGSERIAL      PRIMARY KEY,
    product_code   VARCHAR(30)    NOT NULL UNIQUE,
    product_name   VARCHAR(100)   NOT NULL,
    product_type   VARCHAR(50)    NOT NULL,
    category       VARCHAR(50)    NOT NULL,
    description    TEXT,
    currency_code  VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    min_balance    NUMERIC(18,2),
    max_balance    NUMERIC(18,2),
    is_active      BOOLEAN        NOT NULL DEFAULT TRUE,
    effective_date DATE           NOT NULL,
    expiry_date    DATE,
    attributes     JSONB,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE ref.rate_schedule (
    id             BIGSERIAL    PRIMARY KEY,
    product_code   VARCHAR(30)  NOT NULL REFERENCES ref.product_catalog(product_code),
    rate_type      VARCHAR(30)  NOT NULL,
    rate_tier      INTEGER      NOT NULL DEFAULT 1,
    min_amount     NUMERIC(18,2),
    max_amount     NUMERIC(18,2),
    rate_pct       NUMERIC(8,5) NOT NULL,
    effective_date DATE         NOT NULL,
    expiry_date    DATE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

-- =============================================================================
-- SYSTEM / AUDIT DOMAIN (8 tables)
-- =============================================================================

CREATE TABLE audit.audit_log (
    id             BIGSERIAL    PRIMARY KEY,
    table_schema   VARCHAR(50)  NOT NULL,
    table_name     VARCHAR(100) NOT NULL,
    record_id      BIGINT       NOT NULL,
    operation      CHAR(1)      NOT NULL CHECK (operation IN ('I','U','D')),
    changed_by     VARCHAR(100),
    changed_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    old_values     JSONB,
    new_values     JSONB,
    client_ip      INET,
    session_id     VARCHAR(100),
    correlation_id VARCHAR(100)
);

CREATE INDEX audit_log_table_record_idx ON audit.audit_log (table_name, record_id);
CREATE INDEX audit_log_changed_at_idx   ON audit.audit_log (changed_at);

CREATE TABLE audit.role (
    id          BIGSERIAL    PRIMARY KEY,
    role_code   VARCHAR(50)  NOT NULL UNIQUE,
    role_name   VARCHAR(100) NOT NULL,
    description TEXT,
    is_system   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ
);

CREATE TABLE audit.permission (
    id              BIGSERIAL    PRIMARY KEY,
    permission_code VARCHAR(100) NOT NULL UNIQUE,
    resource        VARCHAR(100) NOT NULL,
    action          VARCHAR(30)  NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE audit.role_permission (
    id            BIGSERIAL   PRIMARY KEY,
    role_id       BIGINT      NOT NULL REFERENCES audit.role(id),
    permission_id BIGINT      NOT NULL REFERENCES audit.permission(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ,
    UNIQUE (role_id, permission_id)
);

CREATE TABLE audit.api_key (
    id           BIGSERIAL    PRIMARY KEY,
    key_hash     VARCHAR(255) NOT NULL UNIQUE,
    key_prefix   VARCHAR(10)  NOT NULL,
    client_name  VARCHAR(100) NOT NULL,
    scopes       TEXT[]       NOT NULL DEFAULT '{}',
    expires_at   TIMESTAMPTZ,
    last_used_at TIMESTAMPTZ,
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ
);

CREATE TABLE audit.session (
    id             BIGSERIAL    PRIMARY KEY,
    session_token  VARCHAR(255) NOT NULL UNIQUE,
    user_ref       VARCHAR(100) NOT NULL,
    role_id        BIGINT       REFERENCES audit.role(id),
    ip_address     INET,
    user_agent     TEXT,
    started_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_active_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at     TIMESTAMPTZ  NOT NULL,
    ended_at       TIMESTAMPTZ,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE audit.user_role (
    id         BIGSERIAL    PRIMARY KEY,
    user_ref   VARCHAR(100) NOT NULL,
    role_id    BIGINT       NOT NULL REFERENCES audit.role(id),
    granted_by VARCHAR(100),
    granted_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    UNIQUE (user_ref, role_id)
);

CREATE TABLE audit.system_config (
    id           BIGSERIAL    PRIMARY KEY,
    config_key   VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT         NOT NULL,
    data_type    VARCHAR(20)  NOT NULL DEFAULT 'string',
    description  TEXT,
    is_encrypted BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ
);

-- =============================================================================
-- PARTY DOMAIN (12 tables)
-- =============================================================================

CREATE TABLE party.party (
    id              BIGSERIAL   PRIMARY KEY,
    party_ref       VARCHAR(30) NOT NULL UNIQUE,
    party_type      VARCHAR(20) NOT NULL CHECK (party_type IN ('INDIVIDUAL','ORGANIZATION','TRUST','ESTATE')),
    status          VARCHAR(20) NOT NULL CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED','DECEASED','DISSOLVED')),
    primary_country VARCHAR(2)  NOT NULL REFERENCES ref.country(country_code),
    tax_country     VARCHAR(2)  REFERENCES ref.country(country_code),
    onboarded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    offboarded_at   TIMESTAMPTZ,
    risk_tier       VARCHAR(10) NOT NULL DEFAULT 'STANDARD' CHECK (risk_tier IN ('LOW','STANDARD','HIGH','PROHIBITED')),
    segment         VARCHAR(30),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE party.individual (
    id               BIGSERIAL      PRIMARY KEY,
    party_id         BIGINT         NOT NULL UNIQUE REFERENCES party.party(id),
    first_name       VARCHAR(100)   NOT NULL,
    middle_name      VARCHAR(100),
    last_name        VARCHAR(100)   NOT NULL,
    suffix           VARCHAR(20),
    date_of_birth    DATE           NOT NULL,
    gender           VARCHAR(10),
    marital_status   VARCHAR(20),
    citizenship      VARCHAR(2)     REFERENCES ref.country(country_code),
    residence_status VARCHAR(20),
    occupation       VARCHAR(100),
    employer_name    VARCHAR(200),
    annual_income    NUMERIC(18,2),
    is_pep           BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE party.organization (
    id                  BIGSERIAL      PRIMARY KEY,
    party_id            BIGINT         NOT NULL UNIQUE REFERENCES party.party(id),
    legal_name          VARCHAR(255)   NOT NULL,
    dba_name            VARCHAR(255),
    org_type            VARCHAR(50)    NOT NULL,
    industry_code       VARCHAR(20),
    date_established    DATE,
    jurisdiction        VARCHAR(2)     REFERENCES ref.country(country_code),
    registration_number VARCHAR(100),
    tax_id              VARCHAR(50),
    is_public           BOOLEAN        NOT NULL DEFAULT FALSE,
    ticker_symbol       VARCHAR(10),
    annual_revenue      NUMERIC(18,2),
    employee_count      INTEGER,
    website             VARCHAR(255),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE party.party_address (
    id             BIGSERIAL    PRIMARY KEY,
    party_id       BIGINT       NOT NULL REFERENCES party.party(id),
    address_type   VARCHAR(20)  NOT NULL CHECK (address_type IN ('HOME','WORK','MAILING','LEGAL','REGISTERED')),
    is_primary     BOOLEAN      NOT NULL DEFAULT FALSE,
    line1          VARCHAR(200) NOT NULL,
    line2          VARCHAR(200),
    line3          VARCHAR(200),
    city           VARCHAR(100) NOT NULL,
    state_province VARCHAR(100),
    postal_code    VARCHAR(20),
    country_code   VARCHAR(2)   NOT NULL REFERENCES ref.country(country_code),
    verified_at    TIMESTAMPTZ,
    effective_from DATE         NOT NULL DEFAULT CURRENT_DATE,
    effective_to   DATE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE party.party_contact (
    id             BIGSERIAL    PRIMARY KEY,
    party_id       BIGINT       NOT NULL REFERENCES party.party(id),
    contact_type   VARCHAR(20)  NOT NULL CHECK (contact_type IN ('EMAIL','MOBILE','HOME_PHONE','WORK_PHONE','FAX')),
    contact_value  VARCHAR(255) NOT NULL,
    is_primary     BOOLEAN      NOT NULL DEFAULT FALSE,
    is_verified    BOOLEAN      NOT NULL DEFAULT FALSE,
    verified_at    TIMESTAMPTZ,
    do_not_contact BOOLEAN      NOT NULL DEFAULT FALSE,
    effective_from DATE         NOT NULL DEFAULT CURRENT_DATE,
    effective_to   DATE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE party.party_identifier (
    id              BIGSERIAL    PRIMARY KEY,
    party_id        BIGINT       NOT NULL REFERENCES party.party(id),
    id_type         VARCHAR(30)  NOT NULL CHECK (id_type IN ('SSN','EIN','PASSPORT','DRIVERS_LICENSE','NATIONAL_ID','ITIN','LEI','SWIFT_BIC')),
    id_number       VARCHAR(100) NOT NULL,
    issuing_country VARCHAR(2)   REFERENCES ref.country(country_code),
    issuing_state   VARCHAR(50),
    issued_date     DATE,
    expiry_date     DATE,
    is_verified     BOOLEAN      NOT NULL DEFAULT FALSE,
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    UNIQUE (party_id, id_type, id_number)
);

CREATE TABLE party.party_relationship (
    id                BIGSERIAL    PRIMARY KEY,
    from_party_id     BIGINT       NOT NULL REFERENCES party.party(id),
    to_party_id       BIGINT       NOT NULL REFERENCES party.party(id),
    relationship_type VARCHAR(50)  NOT NULL,
    ownership_pct     NUMERIC(5,2),
    is_controlling    BOOLEAN      NOT NULL DEFAULT FALSE,
    effective_from    DATE         NOT NULL DEFAULT CURRENT_DATE,
    effective_to      DATE,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE party.party_risk_profile (
    id               BIGSERIAL    PRIMARY KEY,
    party_id         BIGINT       NOT NULL REFERENCES party.party(id),
    risk_score       NUMERIC(5,2) NOT NULL,
    risk_tier        VARCHAR(10)  NOT NULL CHECK (risk_tier IN ('LOW','STANDARD','HIGH','PROHIBITED')),
    risk_factors     JSONB,
    assessed_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    assessed_by      VARCHAR(100),
    next_review_date DATE,
    override_reason  TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE party.party_kyc (
    id               BIGSERIAL   PRIMARY KEY,
    party_id         BIGINT      NOT NULL REFERENCES party.party(id),
    kyc_status       VARCHAR(20) NOT NULL CHECK (kyc_status IN ('PENDING','IN_PROGRESS','APPROVED','REJECTED','EXPIRED')),
    kyc_level        VARCHAR(20) NOT NULL CHECK (kyc_level IN ('BASIC','STANDARD','ENHANCED','EDD')),
    completed_at     TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ,
    reviewed_by      VARCHAR(100),
    rejection_reason TEXT,
    document_refs    TEXT[],
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE party.party_document (
    id              BIGSERIAL    PRIMARY KEY,
    party_id        BIGINT       NOT NULL REFERENCES party.party(id),
    document_type   VARCHAR(50)  NOT NULL,
    document_name   VARCHAR(255) NOT NULL,
    storage_ref     VARCHAR(500) NOT NULL,
    mime_type       VARCHAR(100),
    file_size_bytes BIGINT,
    checksum        VARCHAR(100),
    uploaded_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    expires_at      TIMESTAMPTZ,
    is_verified     BOOLEAN      NOT NULL DEFAULT FALSE,
    verified_at     TIMESTAMPTZ,
    verified_by     VARCHAR(100),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE party.party_preference (
    id            BIGSERIAL    PRIMARY KEY,
    party_id      BIGINT       NOT NULL REFERENCES party.party(id),
    pref_category VARCHAR(50)  NOT NULL,
    pref_key      VARCHAR(100) NOT NULL,
    pref_value    TEXT         NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ,
    UNIQUE (party_id, pref_category, pref_key)
);

CREATE TABLE party.party_segment (
    id             BIGSERIAL    PRIMARY KEY,
    party_id       BIGINT       NOT NULL REFERENCES party.party(id),
    segment_code   VARCHAR(50)  NOT NULL,
    segment_name   VARCHAR(100) NOT NULL,
    sub_segment    VARCHAR(100),
    effective_from DATE         NOT NULL DEFAULT CURRENT_DATE,
    effective_to   DATE,
    assigned_by    VARCHAR(100),
    attributes     JSONB,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

-- =============================================================================
-- ACCOUNTS DOMAIN (10 tables)
-- =============================================================================

CREATE TABLE account.account_product (
    id               BIGSERIAL   PRIMARY KEY,
    product_code     VARCHAR(30) NOT NULL UNIQUE REFERENCES ref.product_catalog(product_code),
    gl_account_code  VARCHAR(20) NOT NULL,
    account_class    VARCHAR(30) NOT NULL,
    allows_overdraft BOOLEAN     NOT NULL DEFAULT FALSE,
    interest_bearing BOOLEAN     NOT NULL DEFAULT FALSE,
    fee_schedule_ref VARCHAR(30),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE account.account (
    id               BIGSERIAL   PRIMARY KEY,
    account_number   VARCHAR(30) NOT NULL UNIQUE,
    party_id         BIGINT      NOT NULL REFERENCES party.party(id),
    product_code     VARCHAR(30) NOT NULL REFERENCES account.account_product(product_code),
    currency_code    VARCHAR(3)  NOT NULL REFERENCES ref.currency(currency_code),
    status           VARCHAR(20) NOT NULL CHECK (status IN ('PENDING','ACTIVE','DORMANT','FROZEN','CLOSED')),
    opened_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at        TIMESTAMPTZ,
    close_reason     VARCHAR(100),
    branch_id        BIGINT,
    relationship_mgr VARCHAR(100),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE account.deposit_account (
    id                BIGSERIAL      PRIMARY KEY,
    account_id        BIGINT         NOT NULL UNIQUE REFERENCES account.account(id),
    subtype           VARCHAR(30)    NOT NULL CHECK (subtype IN ('CHECKING','SAVINGS','MONEY_MARKET','CD','IRA','HSA')),
    current_balance   NUMERIC(18,2)  NOT NULL DEFAULT 0,
    available_balance NUMERIC(18,2)  NOT NULL DEFAULT 0,
    hold_amount       NUMERIC(18,2)  NOT NULL DEFAULT 0,
    overdraft_limit   NUMERIC(18,2)  NOT NULL DEFAULT 0,
    interest_rate_pct NUMERIC(8,5)   NOT NULL DEFAULT 0,
    accrued_interest  NUMERIC(18,6)  NOT NULL DEFAULT 0,
    maturity_date     DATE,
    term_months       INTEGER,
    auto_renew        BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE account.account_balance (
    id            BIGSERIAL      PRIMARY KEY,
    account_id    BIGINT         NOT NULL REFERENCES account.account(id),
    balance_type  VARCHAR(20)    NOT NULL CHECK (balance_type IN ('CURRENT','AVAILABLE','LEDGER','HOLD')),
    balance       NUMERIC(18,2)  NOT NULL,
    currency_code VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    as_of_date    DATE           NOT NULL,
    as_of_time    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE INDEX account_balance_account_date_idx ON account.account_balance (account_id, as_of_date DESC);

CREATE TABLE account.account_interest (
    id             BIGSERIAL    PRIMARY KEY,
    account_id     BIGINT       NOT NULL REFERENCES account.account(id),
    rate_pct       NUMERIC(8,5) NOT NULL,
    rate_type      VARCHAR(20)  NOT NULL CHECK (rate_type IN ('FIXED','VARIABLE','TIERED')),
    effective_from DATE         NOT NULL,
    effective_to   DATE,
    accrual_basis  VARCHAR(10)  NOT NULL DEFAULT 'ACT/365',
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE account.account_statement (
    id              BIGSERIAL      PRIMARY KEY,
    account_id      BIGINT         NOT NULL REFERENCES account.account(id),
    statement_date  DATE           NOT NULL,
    period_start    DATE           NOT NULL,
    period_end      DATE           NOT NULL,
    opening_balance NUMERIC(18,2)  NOT NULL,
    closing_balance NUMERIC(18,2)  NOT NULL,
    total_credits   NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_debits    NUMERIC(18,2)  NOT NULL DEFAULT 0,
    interest_earned NUMERIC(18,2)  NOT NULL DEFAULT 0,
    fees_charged    NUMERIC(18,2)  NOT NULL DEFAULT 0,
    storage_ref     VARCHAR(500),
    generated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    UNIQUE (account_id, statement_date)
);

CREATE TABLE account.account_beneficiary (
    id               BIGSERIAL      PRIMARY KEY,
    account_id       BIGINT         NOT NULL REFERENCES account.account(id),
    beneficiary_type VARCHAR(20)    NOT NULL CHECK (beneficiary_type IN ('PRIMARY','CONTINGENT')),
    beneficiary_name VARCHAR(200)   NOT NULL,
    party_id         BIGINT         REFERENCES party.party(id),
    relationship     VARCHAR(50),
    allocation_pct   NUMERIC(5,2)   NOT NULL,
    date_of_birth    DATE,
    id_type          VARCHAR(30),
    id_number        VARCHAR(100),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE account.account_owner (
    id             BIGSERIAL   PRIMARY KEY,
    account_id     BIGINT      NOT NULL REFERENCES account.account(id),
    party_id       BIGINT      NOT NULL REFERENCES party.party(id),
    ownership_type VARCHAR(30) NOT NULL CHECK (ownership_type IN ('PRIMARY','JOINT','AUTHORIZED_USER','POA','TRUSTEE','CUSTODIAN')),
    ownership_pct  NUMERIC(5,2),
    added_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    removed_at     TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ,
    UNIQUE (account_id, party_id, ownership_type)
);

CREATE TABLE account.account_restriction (
    id               BIGSERIAL    PRIMARY KEY,
    account_id       BIGINT       NOT NULL REFERENCES account.account(id),
    restriction_type VARCHAR(30)  NOT NULL CHECK (restriction_type IN ('FREEZE','DEBIT_BLOCK','CREDIT_BLOCK','GARNISHMENT','LEVY','ESCHEATMENT')),
    reason           VARCHAR(255) NOT NULL,
    imposed_by       VARCHAR(100),
    legal_reference  VARCHAR(200),
    effective_from   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    effective_to     TIMESTAMPTZ,
    lifted_at        TIMESTAMPTZ,
    lifted_by        VARCHAR(100),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE account.account_fee (
    id            BIGSERIAL      PRIMARY KEY,
    account_id    BIGINT         NOT NULL REFERENCES account.account(id),
    fee_type      VARCHAR(50)    NOT NULL,
    fee_code      VARCHAR(30),
    amount        NUMERIC(18,2)  NOT NULL,
    currency_code VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    fee_date      DATE           NOT NULL,
    assessed_at   TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    waived        BOOLEAN        NOT NULL DEFAULT FALSE,
    waived_by     VARCHAR(100),
    waive_reason  VARCHAR(255),
    gl_code       VARCHAR(20),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

-- =============================================================================
-- TRANSACTIONS DOMAIN (8 tables)
-- =============================================================================

CREATE TABLE txn.transaction (
    id               BIGSERIAL      PRIMARY KEY,
    transaction_ref  VARCHAR(50)    NOT NULL UNIQUE,
    account_id       BIGINT         NOT NULL REFERENCES account.account(id),
    transaction_type VARCHAR(30)    NOT NULL CHECK (transaction_type IN ('DEBIT','CREDIT','TRANSFER','FEE','INTEREST','ADJUSTMENT','REVERSAL')),
    channel          VARCHAR(30)    NOT NULL,
    amount           NUMERIC(18,2)  NOT NULL,
    currency_code    VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    fx_rate          NUMERIC(12,6),
    base_amount      NUMERIC(18,2),
    status           VARCHAR(20)    NOT NULL CHECK (status IN ('INITIATED','PENDING','SETTLED','REVERSED','FAILED','CANCELLED')),
    initiated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    value_date       DATE           NOT NULL,
    settlement_date  DATE,
    description      VARCHAR(500),
    merchant_name    VARCHAR(200),
    merchant_category VARCHAR(10),
    reference1       VARCHAR(100),
    reference2       VARCHAR(100),
    initiated_by     VARCHAR(100),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE INDEX txn_transaction_account_idx ON txn.transaction (account_id, initiated_at DESC);
CREATE INDEX txn_transaction_status_idx  ON txn.transaction (status);

CREATE TABLE txn.transaction_leg (
    id             BIGSERIAL      PRIMARY KEY,
    transaction_id BIGINT         NOT NULL REFERENCES txn.transaction(id),
    leg_seq        SMALLINT       NOT NULL DEFAULT 1,
    account_id     BIGINT         NOT NULL REFERENCES account.account(id),
    amount         NUMERIC(18,2)  NOT NULL,
    direction      CHAR(1)        NOT NULL CHECK (direction IN ('D','C')),
    currency_code  VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    gl_account_code VARCHAR(20),
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ,
    UNIQUE (transaction_id, leg_seq)
);

CREATE TABLE txn.transaction_reversal (
    id                 BIGSERIAL    PRIMARY KEY,
    original_txn_id    BIGINT       NOT NULL UNIQUE REFERENCES txn.transaction(id),
    reversal_txn_id    BIGINT       NOT NULL REFERENCES txn.transaction(id),
    reason_code        VARCHAR(30)  NOT NULL,
    reason_description TEXT,
    requested_by       VARCHAR(100),
    approved_by        VARCHAR(100),
    reversed_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted         BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at         TIMESTAMPTZ
);

CREATE TABLE txn.transaction_fee (
    id             BIGSERIAL      PRIMARY KEY,
    transaction_id BIGINT         NOT NULL REFERENCES txn.transaction(id),
    fee_type       VARCHAR(50)    NOT NULL,
    amount         NUMERIC(18,2)  NOT NULL,
    currency_code  VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    waived         BOOLEAN        NOT NULL DEFAULT FALSE,
    waive_reason   VARCHAR(255),
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE txn.transaction_metadata (
    id             BIGSERIAL    PRIMARY KEY,
    transaction_id BIGINT       NOT NULL REFERENCES txn.transaction(id),
    meta_key       VARCHAR(100) NOT NULL,
    meta_value     TEXT,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ,
    UNIQUE (transaction_id, meta_key)
);

CREATE TABLE txn.wire_transfer (
    id                    BIGSERIAL    PRIMARY KEY,
    transaction_id        BIGINT       NOT NULL UNIQUE REFERENCES txn.transaction(id),
    wire_type             VARCHAR(15)  NOT NULL CHECK (wire_type IN ('DOMESTIC','INTERNATIONAL','SWIFT','FEDWIRE','CHIPS')),
    sender_name           VARCHAR(255) NOT NULL,
    sender_account        VARCHAR(50),
    sender_routing        VARCHAR(20),
    sender_bank_name      VARCHAR(255),
    sender_bank_country   VARCHAR(2)   REFERENCES ref.country(country_code),
    receiver_name         VARCHAR(255) NOT NULL,
    receiver_account      VARCHAR(50)  NOT NULL,
    receiver_routing      VARCHAR(20),
    receiver_bank_name    VARCHAR(255),
    receiver_bank_country VARCHAR(2)   REFERENCES ref.country(country_code),
    swift_code            VARCHAR(15),
    purpose_code          VARCHAR(10),
    remittance_info       VARCHAR(500),
    imad                  VARCHAR(50),
    omad                  VARCHAR(50),
    fed_reference         VARCHAR(50),
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted            BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at            TIMESTAMPTZ
);

CREATE TABLE txn.ach_entry (
    id                 BIGSERIAL   PRIMARY KEY,
    transaction_id     BIGINT      NOT NULL UNIQUE REFERENCES txn.transaction(id),
    sec_code           VARCHAR(3)  NOT NULL,
    company_id         VARCHAR(10),
    company_name       VARCHAR(100),
    company_entry_desc VARCHAR(10),
    individual_id      VARCHAR(22),
    individual_name    VARCHAR(22),
    receiver_routing   VARCHAR(9)  NOT NULL,
    receiver_account   VARCHAR(17) NOT NULL,
    account_type       CHAR(1)     NOT NULL CHECK (account_type IN ('C','S')),
    trace_number       VARCHAR(15),
    addenda_info       TEXT,
    batch_number       VARCHAR(20),
    file_date          DATE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted         BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at         TIMESTAMPTZ
);

CREATE TABLE txn.check_item (
    id             BIGSERIAL    PRIMARY KEY,
    transaction_id BIGINT       NOT NULL UNIQUE REFERENCES txn.transaction(id),
    check_number   VARCHAR(20),
    routing_number VARCHAR(9),
    account_number VARCHAR(30),
    payee_name     VARCHAR(200),
    memo           VARCHAR(255),
    check_date     DATE,
    presented_at   TIMESTAMPTZ,
    cleared_at     TIMESTAMPTZ,
    returned_at    TIMESTAMPTZ,
    return_reason  VARCHAR(50),
    image_ref_front VARCHAR(500),
    image_ref_back  VARCHAR(500),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

-- =============================================================================
-- LENDING DOMAIN (12 tables)
-- =============================================================================

CREATE TABLE lending.loan_application (
    id                    BIGSERIAL      PRIMARY KEY,
    application_ref       VARCHAR(30)    NOT NULL UNIQUE,
    party_id              BIGINT         NOT NULL REFERENCES party.party(id),
    product_code          VARCHAR(30)    NOT NULL REFERENCES ref.product_catalog(product_code),
    requested_amount      NUMERIC(18,2)  NOT NULL,
    requested_term_months INTEGER,
    purpose               VARCHAR(100),
    status                VARCHAR(30)    NOT NULL CHECK (status IN ('DRAFT','SUBMITTED','IN_REVIEW','APPROVED','CONDITIONALLY_APPROVED','DECLINED','WITHDRAWN','EXPIRED')),
    submitted_at          TIMESTAMPTZ,
    decision_at           TIMESTAMPTZ,
    decided_by            VARCHAR(100),
    decline_reason        VARCHAR(255),
    credit_score          INTEGER,
    dti_ratio             NUMERIC(5,2),
    ltv_ratio             NUMERIC(5,2),
    channel               VARCHAR(30),
    assigned_officer      VARCHAR(100),
    created_at            TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted            BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at            TIMESTAMPTZ
);

CREATE TABLE lending.loan (
    id                  BIGSERIAL      PRIMARY KEY,
    loan_ref            VARCHAR(30)    NOT NULL UNIQUE,
    application_id      BIGINT         REFERENCES lending.loan_application(id),
    party_id            BIGINT         NOT NULL REFERENCES party.party(id),
    account_id          BIGINT         NOT NULL REFERENCES account.account(id),
    product_code        VARCHAR(30)    NOT NULL REFERENCES ref.product_catalog(product_code),
    currency_code       VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    original_amount     NUMERIC(18,2)  NOT NULL,
    outstanding_balance NUMERIC(18,2)  NOT NULL,
    interest_rate_pct   NUMERIC(8,5)   NOT NULL,
    rate_type           VARCHAR(20)    NOT NULL CHECK (rate_type IN ('FIXED','VARIABLE','ARM')),
    term_months         INTEGER        NOT NULL,
    status              VARCHAR(20)    NOT NULL CHECK (status IN ('ACTIVE','PAID_OFF','DEFAULTED','CHARGED_OFF','IN_MODIFICATION','SOLD')),
    disbursed_at        TIMESTAMPTZ,
    first_payment_date  DATE,
    maturity_date       DATE,
    next_payment_date   DATE,
    next_payment_amount NUMERIC(18,2),
    days_past_due       INTEGER        NOT NULL DEFAULT 0,
    delinquency_status  VARCHAR(20),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE lending.loan_collateral (
    id               BIGSERIAL      PRIMARY KEY,
    loan_id          BIGINT         NOT NULL REFERENCES lending.loan(id),
    collateral_type  VARCHAR(30)    NOT NULL CHECK (collateral_type IN ('REAL_ESTATE','VEHICLE','EQUIPMENT','FINANCIAL_ASSET','INVENTORY','RECEIVABLE','OTHER')),
    description      TEXT           NOT NULL,
    lien_position    SMALLINT       NOT NULL DEFAULT 1,
    appraised_value  NUMERIC(18,2),
    appraised_at     DATE,
    address_line1    VARCHAR(200),
    address_city     VARCHAR(100),
    address_state    VARCHAR(100),
    address_country  VARCHAR(2)     REFERENCES ref.country(country_code),
    vin              VARCHAR(20),
    title_number     VARCHAR(50),
    lien_recorded_at DATE,
    lien_ref         VARCHAR(100),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE lending.loan_schedule (
    id              BIGSERIAL      PRIMARY KEY,
    loan_id         BIGINT         NOT NULL REFERENCES lending.loan(id),
    installment_seq INTEGER        NOT NULL,
    due_date        DATE           NOT NULL,
    principal_due   NUMERIC(18,2)  NOT NULL,
    interest_due    NUMERIC(18,2)  NOT NULL,
    escrow_due      NUMERIC(18,2)  NOT NULL DEFAULT 0,
    fees_due        NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_due       NUMERIC(18,2)  NOT NULL,
    status          VARCHAR(20)    NOT NULL DEFAULT 'SCHEDULED' CHECK (status IN ('SCHEDULED','PAID','PARTIAL','OVERDUE','WAIVED','DEFERRED')),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    UNIQUE (loan_id, installment_seq)
);

CREATE TABLE lending.loan_payment (
    id                BIGSERIAL      PRIMARY KEY,
    loan_id           BIGINT         NOT NULL REFERENCES lending.loan(id),
    transaction_id    BIGINT         REFERENCES txn.transaction(id),
    payment_date      DATE           NOT NULL,
    amount            NUMERIC(18,2)  NOT NULL,
    principal_applied NUMERIC(18,2)  NOT NULL DEFAULT 0,
    interest_applied  NUMERIC(18,2)  NOT NULL DEFAULT 0,
    escrow_applied    NUMERIC(18,2)  NOT NULL DEFAULT 0,
    fees_applied      NUMERIC(18,2)  NOT NULL DEFAULT 0,
    payment_method    VARCHAR(30),
    status            VARCHAR(20)    NOT NULL CHECK (status IN ('PENDING','APPLIED','RETURNED','REVERSED')),
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE lending.loan_modification (
    id                BIGSERIAL    PRIMARY KEY,
    loan_id           BIGINT       NOT NULL REFERENCES lending.loan(id),
    modification_type VARCHAR(30)  NOT NULL CHECK (modification_type IN ('RATE_CHANGE','TERM_EXTENSION','DEFERRAL','FORBEARANCE','PRINCIPAL_REDUCTION','REFINANCE')),
    effective_date    DATE         NOT NULL,
    prior_rate        NUMERIC(8,5),
    new_rate          NUMERIC(8,5),
    prior_maturity    DATE,
    new_maturity      DATE,
    reason            TEXT,
    approved_by       VARCHAR(100),
    investor_approval BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE lending.credit_line (
    id                  BIGSERIAL      PRIMARY KEY,
    line_ref            VARCHAR(30)    NOT NULL UNIQUE,
    party_id            BIGINT         NOT NULL REFERENCES party.party(id),
    account_id          BIGINT         NOT NULL REFERENCES account.account(id),
    product_code        VARCHAR(30)    NOT NULL REFERENCES ref.product_catalog(product_code),
    currency_code       VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    credit_limit        NUMERIC(18,2)  NOT NULL,
    available_credit    NUMERIC(18,2)  NOT NULL,
    outstanding_balance NUMERIC(18,2)  NOT NULL DEFAULT 0,
    interest_rate_pct   NUMERIC(8,5)   NOT NULL,
    cash_advance_rate   NUMERIC(8,5),
    minimum_payment_pct NUMERIC(5,2)   NOT NULL DEFAULT 2.00,
    grace_period_days   INTEGER        NOT NULL DEFAULT 25,
    status              VARCHAR(20)    NOT NULL CHECK (status IN ('ACTIVE','FROZEN','SUSPENDED','CLOSED')),
    review_date         DATE,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE lending.credit_draw (
    id             BIGSERIAL      PRIMARY KEY,
    credit_line_id BIGINT         NOT NULL REFERENCES lending.credit_line(id),
    transaction_id BIGINT         REFERENCES txn.transaction(id),
    draw_ref       VARCHAR(30)    NOT NULL UNIQUE,
    amount         NUMERIC(18,2)  NOT NULL,
    draw_type      VARCHAR(20)    NOT NULL CHECK (draw_type IN ('PURCHASE','CASH_ADVANCE','BALANCE_TRANSFER','OTHER')),
    drawn_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    status         VARCHAR(20)    NOT NULL CHECK (status IN ('PENDING','SETTLED','REVERSED')),
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE TABLE lending.guarantee (
    id                 BIGSERIAL      PRIMARY KEY,
    loan_id            BIGINT         NOT NULL REFERENCES lending.loan(id),
    guarantor_party_id BIGINT         NOT NULL REFERENCES party.party(id),
    guarantee_type     VARCHAR(30)    NOT NULL CHECK (guarantee_type IN ('PERSONAL','CORPORATE','GOVERNMENT','SBA','PARTIAL')),
    guaranteed_amount  NUMERIC(18,2)  NOT NULL,
    guarantee_pct      NUMERIC(5,2),
    effective_date     DATE           NOT NULL,
    expiry_date        DATE,
    executed_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted         BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at         TIMESTAMPTZ
);

CREATE TABLE lending.loan_covenant (
    id              BIGSERIAL      PRIMARY KEY,
    loan_id         BIGINT         NOT NULL REFERENCES lending.loan(id),
    covenant_type   VARCHAR(50)    NOT NULL,
    description     TEXT           NOT NULL,
    metric_name     VARCHAR(100),
    threshold_value NUMERIC(18,4),
    threshold_type  VARCHAR(10)    CHECK (threshold_type IN ('MIN','MAX','RANGE')),
    test_frequency  VARCHAR(20)    NOT NULL DEFAULT 'QUARTERLY',
    last_tested_at  DATE,
    last_result     VARCHAR(20)    CHECK (last_result IN ('PASS','FAIL','WAIVED','NOT_TESTED')),
    breach_at       TIMESTAMPTZ,
    waived_at       TIMESTAMPTZ,
    waive_reason    TEXT,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE lending.appraisal (
    id                BIGSERIAL      PRIMARY KEY,
    collateral_id     BIGINT         NOT NULL REFERENCES lending.loan_collateral(id),
    appraisal_type    VARCHAR(30)    NOT NULL CHECK (appraisal_type IN ('FULL','DESKTOP','DRIVE_BY','AVM','BPO')),
    appraised_value   NUMERIC(18,2)  NOT NULL,
    appraised_at      DATE           NOT NULL,
    appraiser_name    VARCHAR(200),
    appraiser_license VARCHAR(50),
    appraisal_firm    VARCHAR(200),
    report_ref        VARCHAR(500),
    effective_to      DATE,
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE lending.loan_charge (
    id            BIGSERIAL      PRIMARY KEY,
    loan_id       BIGINT         NOT NULL REFERENCES lending.loan(id),
    charge_type   VARCHAR(50)    NOT NULL,
    charge_code   VARCHAR(30),
    amount        NUMERIC(18,2)  NOT NULL,
    currency_code VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    charge_date   DATE           NOT NULL,
    assessed_at   TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    waived        BOOLEAN        NOT NULL DEFAULT FALSE,
    waived_by     VARCHAR(100),
    waive_reason  VARCHAR(255),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

-- =============================================================================
-- CARDS DOMAIN (10 tables)
-- =============================================================================

CREATE TABLE card.card_product (
    id                  BIGSERIAL      PRIMARY KEY,
    product_code        VARCHAR(30)    NOT NULL UNIQUE,
    product_name        VARCHAR(100)   NOT NULL,
    card_network        VARCHAR(20)    NOT NULL CHECK (card_network IN ('VISA','MASTERCARD','AMEX','DISCOVER','UNIONPAY','JCB')),
    card_type           VARCHAR(20)    NOT NULL CHECK (card_type IN ('DEBIT','CREDIT','PREPAID','BUSINESS')),
    reward_program      VARCHAR(50),
    annual_fee          NUMERIC(10,2)  NOT NULL DEFAULT 0,
    foreign_txn_fee_pct NUMERIC(5,3)   NOT NULL DEFAULT 0,
    is_active           BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE card.card_account (
    id                     BIGSERIAL      PRIMARY KEY,
    account_id             BIGINT         NOT NULL UNIQUE REFERENCES account.account(id),
    product_code           VARCHAR(30)    NOT NULL REFERENCES card.card_product(product_code),
    credit_limit           NUMERIC(18,2),
    available_credit       NUMERIC(18,2),
    current_balance        NUMERIC(18,2)  NOT NULL DEFAULT 0,
    statement_balance      NUMERIC(18,2)  NOT NULL DEFAULT 0,
    minimum_payment        NUMERIC(18,2)  NOT NULL DEFAULT 0,
    payment_due_date       DATE,
    cycle_close_day        SMALLINT       NOT NULL DEFAULT 1,
    purchase_rate_pct      NUMERIC(8,5),
    cash_advance_rate      NUMERIC(8,5),
    penalty_rate_pct       NUMERIC(8,5),
    is_penalty_rate_active BOOLEAN        NOT NULL DEFAULT FALSE,
    rewards_balance        NUMERIC(18,2)  NOT NULL DEFAULT 0,
    created_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted             BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at             TIMESTAMPTZ
);

CREATE TABLE card.card (
    id              BIGSERIAL    PRIMARY KEY,
    card_account_id BIGINT       NOT NULL REFERENCES card.card_account(id),
    party_id        BIGINT       NOT NULL REFERENCES party.party(id),
    pan_masked      VARCHAR(20)  NOT NULL,
    pan_token       VARCHAR(100) NOT NULL UNIQUE,
    last_four       CHAR(4)      NOT NULL,
    card_status     VARCHAR(20)  NOT NULL CHECK (card_status IN ('ORDERED','ACTIVE','INACTIVE','BLOCKED','EXPIRED','CANCELLED','LOST','STOLEN')),
    expiry_month    SMALLINT     NOT NULL,
    expiry_year     SMALLINT     NOT NULL,
    cardholder_name VARCHAR(100) NOT NULL,
    card_art_id     VARCHAR(30),
    is_virtual      BOOLEAN      NOT NULL DEFAULT FALSE,
    activated_at    TIMESTAMPTZ,
    blocked_at      TIMESTAMPTZ,
    block_reason    VARCHAR(100),
    issued_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE card.card_transaction (
    id               BIGSERIAL      PRIMARY KEY,
    card_id          BIGINT         NOT NULL REFERENCES card.card(id),
    transaction_id   BIGINT         REFERENCES txn.transaction(id),
    txn_ref          VARCHAR(50)    NOT NULL UNIQUE,
    amount           NUMERIC(18,2)  NOT NULL,
    currency_code    VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    billing_amount   NUMERIC(18,2),
    billing_currency VARCHAR(3)     REFERENCES ref.currency(currency_code),
    fx_rate          NUMERIC(12,6),
    txn_type         VARCHAR(20)    NOT NULL CHECK (txn_type IN ('PURCHASE','REFUND','CASH_ADVANCE','BALANCE_TRANSFER','FEE','ADJUSTMENT')),
    merchant_name    VARCHAR(200),
    merchant_id      VARCHAR(50),
    merchant_category VARCHAR(10),
    merchant_country VARCHAR(2)     REFERENCES ref.country(country_code),
    pos_entry_mode   VARCHAR(10),
    is_recurring     BOOLEAN        NOT NULL DEFAULT FALSE,
    is_contactless   BOOLEAN        NOT NULL DEFAULT FALSE,
    txn_at           TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    posted_at        TIMESTAMPTZ,
    status           VARCHAR(20)    NOT NULL CHECK (status IN ('AUTHORIZED','POSTED','DECLINED','REVERSED')),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE card.card_authorization (
    id               BIGSERIAL      PRIMARY KEY,
    card_id          BIGINT         NOT NULL REFERENCES card.card(id),
    auth_code        VARCHAR(10)    NOT NULL,
    auth_ref         VARCHAR(50)    NOT NULL UNIQUE,
    amount           NUMERIC(18,2)  NOT NULL,
    currency_code    VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    merchant_name    VARCHAR(200),
    merchant_id      VARCHAR(50),
    merchant_category VARCHAR(10),
    merchant_country VARCHAR(2)     REFERENCES ref.country(country_code),
    approval_code    VARCHAR(10),
    response_code    VARCHAR(5),
    status           VARCHAR(20)    NOT NULL CHECK (status IN ('PENDING','APPROVED','DECLINED','EXPIRED','CAPTURED','VOIDED')),
    authorized_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMPTZ,
    captured_at      TIMESTAMPTZ,
    reversal_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE card.card_dispute (
    id                  BIGSERIAL      PRIMARY KEY,
    card_transaction_id BIGINT         NOT NULL REFERENCES card.card_transaction(id),
    dispute_ref         VARCHAR(30)    NOT NULL UNIQUE,
    dispute_reason      VARCHAR(50)    NOT NULL CHECK (dispute_reason IN ('UNAUTHORIZED','DUPLICATE','NOT_RECEIVED','QUALITY_ISSUE','FRAUD','OTHER')),
    disputed_amount     NUMERIC(18,2)  NOT NULL,
    description         TEXT,
    status              VARCHAR(30)    NOT NULL CHECK (status IN ('SUBMITTED','IN_REVIEW','PROVISIONAL_CREDIT','RESOLVED_WIN','RESOLVED_LOSS','WITHDRAWN')),
    filed_at            TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    resolve_notes       TEXT,
    chargeback_ref      VARCHAR(50),
    chargeback_at       TIMESTAMPTZ,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE card.card_reward (
    id                  BIGSERIAL      PRIMARY KEY,
    card_account_id     BIGINT         NOT NULL REFERENCES card.card_account(id),
    card_transaction_id BIGINT         REFERENCES card.card_transaction(id),
    reward_type         VARCHAR(30)    NOT NULL CHECK (reward_type IN ('CASHBACK','POINTS','MILES','NONE')),
    points_earned       NUMERIC(12,2)  NOT NULL DEFAULT 0,
    points_redeemed     NUMERIC(12,2)  NOT NULL DEFAULT 0,
    cash_value          NUMERIC(10,2),
    expiry_date         DATE,
    transaction_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    status              VARCHAR(20)    NOT NULL CHECK (status IN ('PENDING','POSTED','EXPIRED','REVERSED')),
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted          BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at          TIMESTAMPTZ
);

CREATE TABLE card.card_limit (
    id               BIGSERIAL      PRIMARY KEY,
    card_id          BIGINT         NOT NULL REFERENCES card.card(id),
    limit_type       VARCHAR(30)    NOT NULL CHECK (limit_type IN ('DAILY_PURCHASE','DAILY_CASH','SINGLE_TXN','MERCHANT_CATEGORY','INTERNATIONAL','CONTACTLESS')),
    limit_amount     NUMERIC(18,2)  NOT NULL,
    merchant_category VARCHAR(10),
    currency_code    VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    effective_from   DATE           NOT NULL DEFAULT CURRENT_DATE,
    effective_to     DATE,
    set_by           VARCHAR(100),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE card.card_statement (
    id              BIGSERIAL      PRIMARY KEY,
    card_account_id BIGINT         NOT NULL REFERENCES card.card_account(id),
    statement_date  DATE           NOT NULL,
    period_start    DATE           NOT NULL,
    period_end      DATE           NOT NULL,
    opening_balance NUMERIC(18,2)  NOT NULL,
    closing_balance NUMERIC(18,2)  NOT NULL,
    total_purchases NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_payments  NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_fees      NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_interest  NUMERIC(18,2)  NOT NULL DEFAULT 0,
    minimum_payment NUMERIC(18,2)  NOT NULL DEFAULT 0,
    payment_due_date DATE          NOT NULL,
    rewards_earned  NUMERIC(12,2)  NOT NULL DEFAULT 0,
    storage_ref     VARCHAR(500),
    generated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ,
    UNIQUE (card_account_id, statement_date)
);

CREATE TABLE card.card_merchant_restriction (
    id               BIGSERIAL   PRIMARY KEY,
    card_id          BIGINT      NOT NULL REFERENCES card.card(id),
    restriction_type VARCHAR(20) NOT NULL CHECK (restriction_type IN ('BLOCK','ALLOW_ONLY')),
    merchant_category VARCHAR(10),
    merchant_id      VARCHAR(50),
    country_code     VARCHAR(2)  REFERENCES ref.country(country_code),
    reason           VARCHAR(255),
    set_by           VARCHAR(100),
    effective_from   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    effective_to     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

-- =============================================================================
-- COMPLIANCE DOMAIN (8 tables)
-- =============================================================================

CREATE TABLE compliance.aml_alert (
    id                BIGSERIAL    PRIMARY KEY,
    alert_ref         VARCHAR(30)  NOT NULL UNIQUE,
    party_id          BIGINT       REFERENCES party.party(id),
    account_id        BIGINT       REFERENCES account.account(id),
    transaction_id    BIGINT       REFERENCES txn.transaction(id),
    alert_type        VARCHAR(50)  NOT NULL,
    risk_score        NUMERIC(5,2),
    trigger_rules     TEXT[],
    status            VARCHAR(30)  NOT NULL CHECK (status IN ('OPEN','UNDER_REVIEW','ESCALATED','CLOSED_SAR','CLOSED_NO_ACTION','FALSE_POSITIVE')),
    triggered_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    assigned_to       VARCHAR(100),
    reviewed_by       VARCHAR(100),
    reviewed_at       TIMESTAMPTZ,
    disposition_notes TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE compliance.sar_filing (
    id                 BIGSERIAL      PRIMARY KEY,
    sar_ref            VARCHAR(30)    NOT NULL UNIQUE,
    aml_alert_id       BIGINT         REFERENCES compliance.aml_alert(id),
    party_id           BIGINT         NOT NULL REFERENCES party.party(id),
    filing_type        VARCHAR(20)    NOT NULL CHECK (filing_type IN ('INITIAL','CONTINUING','CORRECTION','JOINT')),
    status             VARCHAR(20)    NOT NULL CHECK (status IN ('DRAFT','SUBMITTED','ACKNOWLEDGED','REJECTED')),
    activity_start     DATE           NOT NULL,
    activity_end       DATE           NOT NULL,
    total_amount       NUMERIC(18,2),
    currency_code      VARCHAR(3)     REFERENCES ref.currency(currency_code),
    narrative          TEXT           NOT NULL,
    submitted_at       TIMESTAMPTZ,
    bsa_id             VARCHAR(50),
    filing_institution VARCHAR(200)   NOT NULL,
    prepared_by        VARCHAR(100),
    approved_by        VARCHAR(100),
    created_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted         BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at         TIMESTAMPTZ
);

CREATE TABLE compliance.ctr_filing (
    id               BIGSERIAL      PRIMARY KEY,
    ctr_ref          VARCHAR(30)    NOT NULL UNIQUE,
    party_id         BIGINT         NOT NULL REFERENCES party.party(id),
    account_id       BIGINT         REFERENCES account.account(id),
    filing_type      VARCHAR(20)    NOT NULL CHECK (filing_type IN ('INITIAL','CORRECTION','AMENDMENT')),
    status           VARCHAR(20)    NOT NULL CHECK (status IN ('DRAFT','SUBMITTED','ACKNOWLEDGED','REJECTED')),
    transaction_date DATE           NOT NULL,
    cash_in          NUMERIC(18,2)  NOT NULL DEFAULT 0,
    cash_out         NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_amount     NUMERIC(18,2)  NOT NULL,
    currency_code    VARCHAR(3)     NOT NULL REFERENCES ref.currency(currency_code),
    branch_id        BIGINT,
    submitted_at     TIMESTAMPTZ,
    bsa_id           VARCHAR(50),
    prepared_by      VARCHAR(100),
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN        NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE compliance.sanctions_screening (
    id            BIGSERIAL    PRIMARY KEY,
    screening_ref VARCHAR(30)  NOT NULL UNIQUE,
    party_id      BIGINT       REFERENCES party.party(id),
    transaction_id BIGINT      REFERENCES txn.transaction(id),
    screen_type   VARCHAR(20)  NOT NULL CHECK (screen_type IN ('ONBOARDING','TRANSACTION','PERIODIC','MANUAL')),
    list_name     VARCHAR(100) NOT NULL,
    match_name    VARCHAR(255),
    match_score   NUMERIC(5,2),
    status        VARCHAR(20)  NOT NULL CHECK (status IN ('CLEAR','POTENTIAL_MATCH','CONFIRMED_MATCH','FALSE_POSITIVE')),
    screened_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    reviewed_by   VARCHAR(100),
    reviewed_at   TIMESTAMPTZ,
    notes         TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE compliance.pep_record (
    id            BIGSERIAL   PRIMARY KEY,
    party_id      BIGINT      NOT NULL REFERENCES party.party(id),
    pep_category  VARCHAR(30) NOT NULL CHECK (pep_category IN ('DOMESTIC_PEP','FOREIGN_PEP','IO_PEP','FAMILY_MEMBER','CLOSE_ASSOCIATE')),
    position_held VARCHAR(200),
    country_code  VARCHAR(2)  REFERENCES ref.country(country_code),
    since_date    DATE,
    end_date      DATE,
    source        VARCHAR(100),
    identified_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_by   VARCHAR(100),
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE compliance.adverse_media (
    id          BIGSERIAL    PRIMARY KEY,
    party_id    BIGINT       NOT NULL REFERENCES party.party(id),
    source_name VARCHAR(200) NOT NULL,
    source_url  VARCHAR(500),
    headline    VARCHAR(500) NOT NULL,
    category    VARCHAR(50)  NOT NULL CHECK (category IN ('FRAUD','MONEY_LAUNDERING','TERRORISM','CORRUPTION','TAX_EVASION','SANCTIONS','OTHER')),
    severity    VARCHAR(10)  NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    article_date DATE,
    found_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    reviewed_by VARCHAR(100),
    reviewed_at TIMESTAMPTZ,
    status      VARCHAR(20)  NOT NULL CHECK (status IN ('NEW','UNDER_REVIEW','CONFIRMED','DISMISSED')),
    notes       TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    is_deleted  BOOLEAN      NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ
);

CREATE TABLE compliance.compliance_case (
    id              BIGSERIAL   PRIMARY KEY,
    case_ref        VARCHAR(30) NOT NULL UNIQUE,
    case_type       VARCHAR(50) NOT NULL,
    priority        VARCHAR(10) NOT NULL CHECK (priority IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    party_id        BIGINT      REFERENCES party.party(id),
    aml_alert_id    BIGINT      REFERENCES compliance.aml_alert(id),
    status          VARCHAR(30) NOT NULL CHECK (status IN ('OPEN','IN_REVIEW','PENDING_APPROVAL','CLOSED_ACTION','CLOSED_NO_ACTION')),
    assigned_to     VARCHAR(100),
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at       TIMESTAMPTZ,
    resolution      TEXT,
    resolution_code VARCHAR(30),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE compliance.regulatory_report (
    id               BIGSERIAL   PRIMARY KEY,
    report_ref       VARCHAR(30) NOT NULL UNIQUE,
    report_type      VARCHAR(50) NOT NULL,
    regulator        VARCHAR(100) NOT NULL,
    reporting_period DATE        NOT NULL,
    due_date         DATE        NOT NULL,
    status           VARCHAR(20) NOT NULL CHECK (status IN ('DRAFT','IN_REVIEW','SUBMITTED','ACKNOWLEDGED','REJECTED')),
    submitted_at     TIMESTAMPTZ,
    submission_ref   VARCHAR(100),
    storage_ref      VARCHAR(500),
    prepared_by      VARCHAR(100),
    approved_by      VARCHAR(100),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

-- =============================================================================
-- OPERATIONS DOMAIN (10 tables)
-- =============================================================================

CREATE TABLE ops.branch (
    id              BIGSERIAL   PRIMARY KEY,
    branch_code     VARCHAR(20) NOT NULL UNIQUE,
    branch_name     VARCHAR(100) NOT NULL,
    branch_type     VARCHAR(30) NOT NULL CHECK (branch_type IN ('FULL_SERVICE','LIMITED','ATM_ONLY','DIGITAL','MOBILE')),
    routing_number  VARCHAR(9),
    address_line1   VARCHAR(200) NOT NULL,
    address_city    VARCHAR(100) NOT NULL,
    address_state   VARCHAR(100),
    address_country VARCHAR(2)  NOT NULL REFERENCES ref.country(country_code),
    postal_code     VARCHAR(20),
    phone           VARCHAR(30),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    opened_at       DATE,
    closed_at       DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE ops.employee (
    id               BIGSERIAL   PRIMARY KEY,
    employee_ref     VARCHAR(20) NOT NULL UNIQUE,
    party_id         BIGINT      REFERENCES party.party(id),
    branch_id        BIGINT      REFERENCES ops.branch(id),
    manager_id       BIGINT      REFERENCES ops.employee(id),
    first_name       VARCHAR(100) NOT NULL,
    last_name        VARCHAR(100) NOT NULL,
    title            VARCHAR(100),
    department       VARCHAR(100),
    email            VARCHAR(255),
    status           VARCHAR(20) NOT NULL CHECK (status IN ('ACTIVE','INACTIVE','LEAVE','TERMINATED')),
    hire_date        DATE        NOT NULL,
    termination_date DATE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE ops.channel (
    id           BIGSERIAL   PRIMARY KEY,
    channel_code VARCHAR(20) NOT NULL UNIQUE,
    channel_name VARCHAR(100) NOT NULL,
    channel_type VARCHAR(30) NOT NULL CHECK (channel_type IN ('BRANCH','ONLINE','MOBILE','ATM','PHONE','API','IVR')),
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted   BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ
);

CREATE TABLE ops.service_request (
    id               BIGSERIAL   PRIMARY KEY,
    request_ref      VARCHAR(30) NOT NULL UNIQUE,
    party_id         BIGINT      NOT NULL REFERENCES party.party(id),
    account_id       BIGINT      REFERENCES account.account(id),
    request_type     VARCHAR(50) NOT NULL,
    category         VARCHAR(50),
    subject          VARCHAR(255) NOT NULL,
    description      TEXT,
    priority         VARCHAR(10) NOT NULL DEFAULT 'NORMAL' CHECK (priority IN ('LOW','NORMAL','HIGH','URGENT')),
    status           VARCHAR(20) NOT NULL CHECK (status IN ('OPEN','IN_PROGRESS','PENDING_CUSTOMER','RESOLVED','CLOSED','CANCELLED')),
    channel_id       BIGINT      REFERENCES ops.channel(id),
    assigned_to      VARCHAR(100),
    branch_id        BIGINT      REFERENCES ops.branch(id),
    opened_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at      TIMESTAMPTZ,
    closed_at        TIMESTAMPTZ,
    resolution_code  VARCHAR(30),
    resolution_notes TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at       TIMESTAMPTZ
);

CREATE TABLE ops.work_item (
    id            BIGSERIAL   PRIMARY KEY,
    work_item_ref VARCHAR(30) NOT NULL UNIQUE,
    item_type     VARCHAR(50) NOT NULL,
    source_ref    VARCHAR(100),
    queue_name    VARCHAR(100) NOT NULL,
    priority      SMALLINT    NOT NULL DEFAULT 50,
    status        VARCHAR(20) NOT NULL CHECK (status IN ('QUEUED','IN_PROGRESS','COMPLETED','FAILED','CANCELLED','ON_HOLD')),
    assigned_to   VARCHAR(100),
    payload       JSONB,
    attempt_count INTEGER     NOT NULL DEFAULT 0,
    max_attempts  INTEGER     NOT NULL DEFAULT 3,
    queued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at    TIMESTAMPTZ,
    completed_at  TIMESTAMPTZ,
    due_by        TIMESTAMPTZ,
    error_message TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE ops.notification (
    id                BIGSERIAL   PRIMARY KEY,
    party_id          BIGINT      NOT NULL REFERENCES party.party(id),
    notification_type VARCHAR(50) NOT NULL,
    channel           VARCHAR(20) NOT NULL CHECK (channel IN ('EMAIL','SMS','PUSH','IN_APP','LETTER')),
    subject           VARCHAR(255),
    body              TEXT        NOT NULL,
    template_ref      VARCHAR(100),
    recipient_address VARCHAR(255) NOT NULL,
    status            VARCHAR(20) NOT NULL CHECK (status IN ('QUEUED','SENT','DELIVERED','FAILED','BOUNCED')),
    scheduled_at      TIMESTAMPTZ,
    sent_at           TIMESTAMPTZ,
    delivered_at      TIMESTAMPTZ,
    error_message     TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted        BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at        TIMESTAMPTZ
);

CREATE TABLE ops.batch_job (
    id              BIGSERIAL   PRIMARY KEY,
    job_code        VARCHAR(50) NOT NULL UNIQUE,
    job_name        VARCHAR(100) NOT NULL,
    job_type        VARCHAR(30) NOT NULL,
    schedule_cron   VARCHAR(100),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    timeout_seconds INTEGER     NOT NULL DEFAULT 3600,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE ops.batch_job_run (
    id              BIGSERIAL   PRIMARY KEY,
    job_id          BIGINT      NOT NULL REFERENCES ops.batch_job(id),
    run_ref         VARCHAR(30) NOT NULL UNIQUE,
    status          VARCHAR(20) NOT NULL CHECK (status IN ('RUNNING','COMPLETED','FAILED','CANCELLED','TIMED_OUT')),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    records_read    BIGINT      NOT NULL DEFAULT 0,
    records_written BIGINT      NOT NULL DEFAULT 0,
    records_failed  BIGINT      NOT NULL DEFAULT 0,
    error_message   TEXT,
    parameters      JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at      TIMESTAMPTZ
);

CREATE TABLE ops.scheduled_task (
    id            BIGSERIAL   PRIMARY KEY,
    task_ref      VARCHAR(30) NOT NULL UNIQUE,
    task_type     VARCHAR(50) NOT NULL,
    entity_type   VARCHAR(50),
    entity_id     BIGINT,
    scheduled_for TIMESTAMPTZ NOT NULL,
    status        VARCHAR(20) NOT NULL CHECK (status IN ('PENDING','RUNNING','COMPLETED','FAILED','CANCELLED')),
    attempt_count INTEGER     NOT NULL DEFAULT 0,
    max_attempts  INTEGER     NOT NULL DEFAULT 3,
    payload       JSONB,
    completed_at  TIMESTAMPTZ,
    error_message TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ
);

CREATE TABLE ops.event_outbox (
    id             BIGSERIAL   PRIMARY KEY,
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id   BIGINT      NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','PUBLISHED','FAILED')),
    attempt_count  INTEGER     NOT NULL DEFAULT 0,
    published_at   TIMESTAMPTZ,
    error_message  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted     BOOLEAN     NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ
);

CREATE INDEX event_outbox_pending_idx ON ops.event_outbox (status, created_at) WHERE status = 'PENDING';

-- =============================================================================
-- WART DOMAIN (5 intentionally messy tables — no FK constraints)
-- =============================================================================

-- Denormalized customer summary rebuilt nightly
CREATE TABLE wart.customer_summary (
    customer_id           INTEGER,
    customer_ref          VARCHAR(30),
    full_name             VARCHAR(300),
    email                 VARCHAR(255),
    phone                 VARCHAR(50),
    address               VARCHAR(500),
    date_of_birth         VARCHAR(20),    -- stored as string; legacy ETL can't handle DATE
    ssn_last4             CHAR(4),
    kyc_status            VARCHAR(20),
    risk_tier             VARCHAR(10),
    total_accounts        INTEGER,
    total_deposits        NUMERIC(20,2),
    total_loans           NUMERIC(20,2),
    total_credit_limits   NUMERIC(20,2),
    total_card_spend_ytd  NUMERIC(20,2),
    last_login_date       VARCHAR(30),    -- also a string; same ETL tool
    account_list          TEXT,           -- comma-separated account numbers
    loan_list             TEXT,
    card_list             TEXT,
    segment               VARCHAR(50),
    sub_segment           VARCHAR(50),
    branch_name           VARCHAR(100),
    relationship_mgr      VARCHAR(100),
    open_alerts           INTEGER,
    open_cases            INTEGER,
    ytd_interest_earned   NUMERIC(20,2),
    ytd_fees_paid         NUMERIC(20,2),
    ytd_transactions      INTEGER,
    profitability_score   NUMERIC(8,2),
    last_refreshed_at     TIMESTAMP,      -- intentionally no timezone
    refresh_run_id        VARCHAR(50),
    extra1                VARCHAR(255),   -- "just in case" columns from original spec
    extra2                VARCHAR(255),
    extra3                VARCHAR(255),
    notes                 TEXT
);

-- Legacy account map from 2009 core migration — no PK, no FKs
CREATE TABLE wart.legacy_account_map (
    legacy_system          VARCHAR(20),
    legacy_account_id      VARCHAR(50),
    legacy_customer_id     VARCHAR(50),
    new_account_number     VARCHAR(30),
    new_party_ref          VARCHAR(30),
    account_type_old       VARCHAR(30),
    account_type_new       VARCHAR(30),
    migrated_at            TIMESTAMP,
    migration_batch        VARCHAR(30),
    migration_status       VARCHAR(20),
    balance_at_migration   NUMERIC(20,4),
    discrepancy_amount     NUMERIC(20,4),
    discrepancy_notes      TEXT,
    verified_by            VARCHAR(100),
    verified_at            TIMESTAMP,
    system_notes           TEXT,
    flag1                  VARCHAR(1),
    flag2                  VARCHAR(1),
    flag3                  VARCHAR(1),
    raw_source_data        TEXT           -- JSON blob stored as TEXT; ETL limitation
);

-- Flat card transaction reporting table rebuilt nightly; no normalization
CREATE TABLE wart.card_transaction_flat (
    row_id                 BIGSERIAL,
    report_date            DATE,
    card_id                BIGINT,
    card_last_four         CHAR(4),
    cardholder_name        VARCHAR(200),
    cardholder_party_ref   VARCHAR(30),
    account_number         VARCHAR(30),
    product_code           VARCHAR(30),
    product_name           VARCHAR(100),
    card_network           VARCHAR(20),
    txn_ref                VARCHAR(50),
    txn_date               TIMESTAMP,
    txn_type               VARCHAR(30),
    merchant_name          VARCHAR(200),
    merchant_id            VARCHAR(50),
    merchant_category      VARCHAR(10),
    merchant_category_desc VARCHAR(100),
    merchant_country       CHAR(2),
    merchant_city          VARCHAR(100),
    txn_amount             NUMERIC(18,2),
    txn_currency           CHAR(3),
    billing_amount         NUMERIC(18,2),
    billing_currency       CHAR(3),
    fx_rate                NUMERIC(12,6),
    is_international       BOOLEAN,
    is_contactless         BOOLEAN,
    is_recurring           BOOLEAN,
    pos_entry_mode         VARCHAR(10),
    status                 VARCHAR(20),
    is_disputed            BOOLEAN,
    dispute_status         VARCHAR(30),
    rewards_type           VARCHAR(30),
    rewards_earned         NUMERIC(12,2),
    rewards_redeemed       NUMERIC(12,2),
    auth_code              VARCHAR(10),
    response_code          VARCHAR(5),
    segment                VARCHAR(50),
    sub_segment            VARCHAR(50),
    relationship_mgr       VARCHAR(100),
    branch_name            VARCHAR(100),
    inserted_at            TIMESTAMP DEFAULT NOW()
);

-- Raw feed staging from core banking; 60+ columns, mostly nullable
CREATE TABLE wart.transaction_staging (
    stg_id                BIGSERIAL    PRIMARY KEY,
    source_system         VARCHAR(30),
    feed_file             VARCHAR(255),
    feed_batch            VARCHAR(50),
    feed_line_number      INTEGER,
    raw_record            TEXT,
    txn_ref               VARCHAR(50),
    txn_date              VARCHAR(30),   -- raw string; sign conventions differ per source
    value_date            VARCHAR(30),
    settlement_date       VARCHAR(30),
    posting_date          VARCHAR(30),
    account_number        VARCHAR(30),
    account_number_alt    VARCHAR(30),   -- alternate format from pre-2015 system
    customer_id           VARCHAR(30),
    amount                VARCHAR(30),   -- stored as string; sign conventions differ
    amount_numeric        NUMERIC(20,4),
    currency_code         CHAR(3),
    base_amount           NUMERIC(20,4),
    base_currency         CHAR(3),
    fx_rate               NUMERIC(12,6),
    transaction_type      VARCHAR(30),
    transaction_type_code VARCHAR(10),
    channel_code          VARCHAR(20),
    channel_code_alt      VARCHAR(20),
    debit_credit          CHAR(1),
    description1          VARCHAR(255),
    description2          VARCHAR(255),
    description3          VARCHAR(255),
    reference1            VARCHAR(100),
    reference2            VARCHAR(100),
    reference3            VARCHAR(100),
    reference4            VARCHAR(100),
    merchant_name         VARCHAR(200),
    merchant_id           VARCHAR(50),
    merchant_category     VARCHAR(10),
    mcc_description       VARCHAR(100),
    merchant_country      CHAR(2),
    merchant_city         VARCHAR(100),
    merchant_state        VARCHAR(50),
    merchant_postal       VARCHAR(20),
    counterparty_name     VARCHAR(255),
    counterparty_account  VARCHAR(50),
    counterparty_routing  VARCHAR(20),
    counterparty_bank     VARCHAR(255),
    wire_imad             VARCHAR(50),
    wire_omad             VARCHAR(50),
    ach_sec_code          VARCHAR(3),
    ach_trace             VARCHAR(15),
    check_number          VARCHAR(20),
    check_routing         VARCHAR(9),
    card_last_four        CHAR(4),
    auth_code             VARCHAR(10),
    pos_entry_mode        VARCHAR(10),
    original_txn_ref      VARCHAR(50),
    reversal_reason       VARCHAR(50),
    gl_code               VARCHAR(20),
    cost_center           VARCHAR(20),
    branch_code           VARCHAR(20),
    teller_id             VARCHAR(20),
    terminal_id           VARCHAR(20),
    is_international      VARCHAR(1),
    is_hold               VARCHAR(1),
    hold_release_date     VARCHAR(30),
    narrative_line1       VARCHAR(255),
    narrative_line2       VARCHAR(255),
    narrative_line3       VARCHAR(255),
    extra_field_01        VARCHAR(255),
    extra_field_02        VARCHAR(255),
    extra_field_03        VARCHAR(255),
    extra_field_04        VARCHAR(255),
    extra_field_05        VARCHAR(255),
    loaded_at             TIMESTAMP    NOT NULL DEFAULT NOW(),
    processed_at          TIMESTAMP,
    process_status        VARCHAR(20)  DEFAULT 'PENDING',
    process_error         TEXT,
    reconciliation_status VARCHAR(20),
    reconciled_at         TIMESTAMP,
    txn_id_mapped         BIGINT       -- set post-mapping to txn.transaction; no FK by design
);

-- Dashboard query cache rebuilt every 15 minutes by cron
CREATE TABLE wart.reporting_cache (
    cache_key        VARCHAR(200) PRIMARY KEY,
    cache_category   VARCHAR(50),
    report_name      VARCHAR(100),
    data_json        TEXT,          -- stringified JSON, not JSONB; ETL tool limitation
    row_count        INTEGER,
    generated_at     TIMESTAMP    NOT NULL DEFAULT NOW(),
    expires_at       TIMESTAMP,
    generation_ms    INTEGER,
    source_tables    TEXT,          -- comma-separated; see above re: ETL tool
    filter_params    TEXT,          -- URL-encoded query string stored as text
    version          INTEGER      NOT NULL DEFAULT 1,
    is_stale         BOOLEAN      NOT NULL DEFAULT FALSE,
    last_access_at   TIMESTAMP,
    access_count     INTEGER      NOT NULL DEFAULT 0,
    generated_by     VARCHAR(50),
    notes            TEXT
);
