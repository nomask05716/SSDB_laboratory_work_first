CREATE SCHEMA IF NOT EXISTS app;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
SET ROLE app_owner;

CREATE TABLE app.employee ( --сотрудники банка
    employee_id SERIAL PRIMARY KEY,
    branch_id SMALLINT NOT NULL --отделение банка
        REFERENCES ref.branch(branch_id) ON DELETE RESTRICT,
    db_username VARCHAR(80) NOT NULL UNIQUE, --имя пользователя БД
    last_name VARCHAR(80) NOT NULL, -- Фамилия
    first_name VARCHAR(80) NOT NULL, -- Имя
    job_title VARCHAR(100) NOT NULL, --Должность
    access_role VARCHAR(20) NOT NULL --Роль доступа
        CHECK (access_role IN ('app_reader','app_writer','app_owner','auditor','ddl_admin','dml_admin','security_admin')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE, --состояние учетной записи
    hired_at DATE NOT NULL DEFAULT CURRENT_DATE --дата приема на работу
);

CREATE TABLE app.customer ( --клиент банка
    customer_id BIGSERIAL PRIMARY KEY, 
    employee_id INTEGER NOT NULL 
        REFERENCES app.employee(employee_id) ON DELETE RESTRICT,
    branch_id SMALLINT NOT NULL 
        REFERENCES ref.branch(branch_id) ON DELETE RESTRICT,
    last_name VARCHAR(80) NOT NULL, --фамилия
    first_name VARCHAR(80) NOT NULL, --имя
    middle_name VARCHAR(80), --отчество
    birth_date DATE NOT NULL --дата рождения
        CHECK (birth_date <= CURRENT_DATE - INTERVAL '14 years'),
    passport_enc BYTEA NOT NULL UNIQUE, --серия номер в зашифрованном виде
    tax_id_enc BYTEA NOT NULL UNIQUE, -- ИНН в зашифрованном виде
    tax_id_hash BYTEA UNIQUE NOT NULL, --hash ИНН
    email VARCHAR(254) NOT NULL --почта
        CHECK (email ~ '^[-a-z0-9!#$%&''*+/=?^_`{|}~]+(\.[-a-z0-9!#$%&''*+/=?^_`{|}~]+)*@([a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\.)*(aero|arpa|asia|biz|cat|com|coop|edu|gov|info|int|jobs|mil|mobi|museum|name|net|org|pro|tel|travel|[a-z][a-z])$'),
    phone VARCHAR(18) NOT NULL --номер
        CHECK (phone ~ '^((8|\+7)[ -]?)?(\(?\d{3}\)?[ -]?)?[\d -]{7,10}$'), 
    kyc_status VARCHAR(15) NOT NULL DEFAULT 'ABSENT' --KYC
        CHECK (kyc_status IN ('VERIFIED','REJECTED','BLOCKED','ABSENT')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), --время создания
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now() --время обновления данных
);

CREATE TABLE app.account ( --клиентский счет
    account_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL --клиент
        REFERENCES app.customer(customer_id) ON DELETE RESTRICT,
    currency_code VARCHAR(3) NOT NULL --валюта
        REFERENCES ref.currency(currency_code) ON DELETE RESTRICT,
    account_number VARCHAR(34) NOT NULL UNIQUE, --номер счета
    balance NUMERIC(11,3) NOT NULL DEFAULT 0, --баланс
    overdraft_limit NUMERIC(7,2) NOT NULL DEFAULT 0 --допустимый отрицательный баланс
        CHECK (overdraft_limit BETWEEN 0 AND 99999.99),
    status VARCHAR(10) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),--время открытия
    closed_at TIMESTAMPTZ, --время закрытия
    CHECK (
        (status = 'CLOSED' AND closed_at IS NOT NULL)
        OR
        (status IN ('ACTIVE', 'FROZEN') AND closed_at IS NULL)
    ),
    CHECK (balance >= -overdraft_limit),
    CHECK (closed_at IS NULL OR closed_at >= opened_at)
);

CREATE TABLE app.card ( --карта
    card_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL 
        REFERENCES app.account(account_id) ON DELETE RESTRICT,
    pan_token VARCHAR(64) NOT NULL UNIQUE,--токен номера карты
    pan_token_enc BYTEA NOT NULL,--зашифрованный токен
    holder_name VARCHAR(100) NOT NULL,--имя владельца карты
    expiry_month SMALLINT NOT NULL --месяц окончания действия карты
        CHECK (expiry_month BETWEEN 1 AND 12),
    expiry_year SMALLINT NOT NULL --год окончания действия карты 
        CHECK (expiry_year >= 2000),
    status VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' --статус карты
        CHECK (status IN ('ACTIVE','BLOCKED')),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT now() --дата выпуска
);

CREATE TABLE app.transaction ( --транзакции
    transaction_id BIGSERIAL PRIMARY KEY,
    transaction_type_id SMALLINT NOT NULL 
        REFERENCES ref.transaction_type(transaction_type_id) ON DELETE RESTRICT,
    source_account_id BIGINT NOT NULL
        REFERENCES app.account(account_id) ON DELETE RESTRICT,
    target_account_id BIGINT NOT NULL
        REFERENCES app.account(account_id) ON DELETE RESTRICT,
    currency_code VARCHAR(3) NOT NULL 
        REFERENCES ref.currency(currency_code) ON DELETE RESTRICT,
    transaction_uuid UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(), --UUID транзакции
    amount NUMERIC(11,3) NOT NULL  --сумма транзакции
        CHECK (amount > 0),
    description VARCHAR(300), --назначение транзакции
    status VARCHAR(12) NOT NULL DEFAULT 'PENDING' --статус транзакции
        CHECK (status IN ('PENDING','COMPLETED','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), --время создания транзакции
    completed_at TIMESTAMPTZ, --время выполнения транзакции
    CHECK (
        (status IN ('COMPLETED', 'REJECTED') AND completed_at IS NOT NULL)
        OR
        (status = 'PENDING' AND completed_at IS NULL)
    ),
    CHECK (source_account_id IS NOT NULL OR target_account_id IS NOT NULL),
    CHECK (source_account_id IS DISTINCT FROM target_account_id)
);

CREATE TABLE app.auth_credential ( --креды клиентов
    credential_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL UNIQUE 
        REFERENCES app.customer(customer_id) ON DELETE RESTRICT,
    login VARCHAR(80) NOT NULL UNIQUE, --логин
    password_hash VARCHAR(255) NOT NULL, --хеш пароля
    mfa_secret_enc BYTEA, --секрет для одноразовых кодов
    failed_attempts SMALLINT NOT NULL DEFAULT 0  --количество неудачных входов
        CHECK (failed_attempts >= 0),
    locked_until TIMESTAMPTZ NOT NULL DEFAULT now(), --дата блокировки
    password_changed TIMESTAMPTZ NOT NULL DEFAULT now(),--дата последней смены пароля
    last_login_at TIMESTAMPTZ --дата последнего захода клиента
);

CREATE TABLE app.fraund_alert ( --115 ФЗ
    alert_id BIGSERIAL PRIMARY KEY,
    transaction_id BIGINT NOT NULL 
        REFERENCES app.transaction(transaction_id) ON DELETE RESTRICT,
    reviewed_by INTEGER NOT NULL
        REFERENCES app.employee(employee_id) ON DELETE RESTRICT,
    rule_code VARCHAR(40) NOT NULL, --код правила
    risk_score SMALLINT NOT NULL --оценка риска
        CHECK (risk_score BETWEEN 0 AND 100),
    status VARCHAR(14) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('TRUE_POSITIVE','FALSE_POSITIVE','PENDING')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(), --дата создания алерта
    resolved_at TIMESTAMPTZ, --дата закрытия алерта
    CHECK (
        (status = 'PENDING' AND resolved_at IS NULL)
        OR
        (status IN ('TRUE_POSITIVE', 'FALSE_POSITIVE') AND resolved_at IS NOT NULL)
    )
);