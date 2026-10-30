SELECT current_user, session_user;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE app_reader
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE app_writer
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE app_owner
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE audit_owner
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE auditor
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE ddl_admin
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE dml_admin
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

CREATE ROLE security_admin
    NOLOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS;

--установка схем
CREATE SCHEMA ref AUTHORIZATION app_owner; --справочники
CREATE SCHEMA app AUTHORIZATION app_owner; --основные сущности предметной области
CREATE SCHEMA audit AUTHORIZATION audit_owner; --журналы аудита
CREATE SCHEMA stg AUTHORIZATION dml_admin; --импортные данные

--сущности схемы ref:

SET ROLE app_owner;

CREATE TABLE ref.branch ( --отделения банка
    branch_id SMALLINT PRIMARY KEY 
        CHECK (branch_id > 0),
    branch_code VARCHAR(5) NOT NULL UNIQUE --код отделения
        CHECK (branch_code ~ '^[^-]+-[^-]+$'),
    branch_name VARCHAR(60) NOT NULL UNIQUE, --название отделения
    city VARCHAR(30) NOT NULL, --название города, где расположено отделениe
    address VARCHAR(250) NOT NULL UNIQUE --полный адрес отделения
        CHECK (POSITION('Российская Федерация' IN address) > 0),
    phone VARCHAR(18) NOT NULL, --номер оператора отделения
    is_active BOOLEAN NOT NULL DEFAULT TRUE --состояние отделения
);

CREATE TABLE ref.currency ( --валюта
    currency_code VARCHAR(3) PRIMARY KEY, -- ISO 4217
    currency_name VARCHAR(30) NOT NULL, -- название валюты
    minor_units   SMALLINT NOT NULL DEFAULT 2 --количество знаков после запятой
        CHECK (minor_units BETWEEN 0 AND 4),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE -- состояние валюты
);

CREATE TABLE ref.transaction_type ( --типы транзакций
    transaction_type_id SMALLINT PRIMARY KEY,
    type_name           VARCHAR(30) NOT NULL, --название финансовой транзакции
    daily_limit         NUMERIC(3) --дневной лимит
        CHECK ((daily_limit IS NULL) OR (daily_limit BETWEEN 1 and 30)),
    requires_2fa        BOOLEAN  NOT NULL DEFAULT FALSE, --нужна ли двухфакторная авторизация
    fraund_check_level   SMALLINT NOT NULL DEFAULT 1 --глубина антифрод проверки
        CHECK (fraund_check_level BETWEEN 0 AND 3)
);
--schema/ref.sql

--сущности схемы app:
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

--сущности схемы audit. Welcome to schema/audit.sql:
RESET ROLE;

GRANT USAGE ON SCHEMA app TO audit_owner;
GRANT USAGE ON SCHEMA ref TO audit_owner;

GRANT REFERENCES (employee_id)
ON TABLE app.employee
TO audit_owner;

GRANT REFERENCES (transaction_id)
ON TABLE app.transaction
TO audit_owner;

GRANT SELECT (employee_id, db_username)
ON TABLE app.employee
TO audit_owner;

SET ROLE audit_owner;

CREATE TABLE audit.login_log (
    log_id BIGSERIAL PRIMARY KEY,
    employee_id INTEGER 
        REFERENCES app.employee(employee_id) ON DELETE RESTRICT,
    db_user VARCHAR(80) NOT NULL, 
    client_ip INET NOT NULL,
    action VARCHAR(10) NOT NULL
        CHECK (action IN ('LOGIN','LOGOUT','SELECT','INSERT','UPDATE','DELETE','DENIED')),
    object_name VARCHAR(30) NOT NULL, --объект, к которому обращались
    success BOOLEAN NOT NULL, --статус обращение к объекту
    login_time TIMESTAMPTZ NOT NULL DEFAULT now() --время лога
);

CREATE TABLE audit.transaction_audit ( --логи транзакций
    audit_id BIGSERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL
        REFERENCES app.employee(employee_id) ON DELETE RESTRICT,
    transaction_id BIGINT NOT NULL
        REFERENCES app.transaction(transaction_id) ON DELETE RESTRICT,
    operation VARCHAR(1) NOT NULL --добавление,обновление,удаление
        CHECK (operation IN ('I','U','D')),
    old_values JSONB NOT NULL,
    new_values JSONB NOT NULL,
    changed_by VARCHAR(80) NOT NULL DEFAULT current_user, --кто изменил
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now() -- когда изменил
);

--сущности схемы stg. Welcome to schema/stg.sql:
RESET ROLE;

GRANT USAGE ON SCHEMA app TO dml_admin;

GRANT REFERENCES (customer_id)
ON TABLE app.customer
TO dml_admin;

GRANT REFERENCES (transaction_id)
ON TABLE app.transaction
TO dml_admin;
SET ROLE dml_admin;

CREATE TABLE stg.customer_import ( --ПД кдиента, remove after operation! Else 152 ФЗ
    import_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL
        REFERENCES app.customer(customer_id) ON DELETE RESTRICT,
    raw_fullname VARCHAR(250), --ФИО
    raw_birth VARCHAR(20), --дата рождения
    raw_passport VARCHAR(100), --паспортные данные
    raw_tax_id VARCHAR(30), --ИНН
    raw_phone VARCHAR(18), --телефон
    load_status VARCHAR(10) NOT NULL DEFAULT 'NEW'
        CHECK (load_status IN ('NEW','VALID','ERROR','LOADED')),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now() --время загрузки
);

CREATE TABLE stg.transaction_import (
    import_id BIGSERIAL PRIMARY KEY,
    transaction_id BIGINT NOT NULL
        REFERENCES app.transaction(transaction_id) ON DELETE RESTRICT,
    external_id UUID NOT NULL, --импортируемый UUID
    raw_source_acc VARCHAR(40), --счет отправителя
    raw_target_acc VARCHAR(40), --счет получателя
    raw_amount VARCHAR(30), --сумма
    raw_currency VARCHAR(10), --валюта
    load_status VARCHAR(10) NOT NULL DEFAULT 'NEW'
        CHECK (load_status IN ('NEW','VALID','ERROR','LOADED')),
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT now() --время загрузки
);
SET ROLE postgres;

BEGIN;

SET ROLE postgres;

CREATE OR REPLACE FUNCTION audit.log_login_event() 
RETURNS event_trigger 
LANGUAGE plpgsql
SECURITY DEFINER 
SET search_path = pg_catalog, audit, pg_temp
AS $$
BEGIN
    IF pg_is_in_recovery() THEN
        RETURN;
    END IF;
    INSERT INTO audit.login_log (
        employee_id,
        db_user,
        client_ip,
        action,
        object_name,
        success,
        login_time
    )
    VALUES (
        (SELECT employee_id FROM app.employee WHERE db_username = session_user LIMIT 1),
        session_user,        
        COALESCE(inet_client_addr(), '127.0.0.1'::inet),
        'LOGIN',             
        'database',          
        TRUE,                
        clock_timestamp()  
    );
END;
$$;

CREATE EVENT TRIGGER trg_login_audit 
ON login 
EXECUTE FUNCTION audit.log_login_event();
ALTER EVENT TRIGGER trg_login_audit ENABLE ALWAYS;

CREATE OR REPLACE FUNCTION audit.trigger_transaction_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit, pg_temp
AS $$
DECLARE
    v_employee_id INTEGER;
BEGIN
    v_employee_id := (SELECT employee_id FROM app.employee WHERE db_username = current_user LIMIT 1);
    v_employee_id := COALESCE(v_employee_id, 1); 

    INSERT INTO audit.transaction_audit (
        employee_id, transaction_id, operation, old_values, new_values, changed_by, changed_at
    ) VALUES (
        v_employee_id,
        COALESCE(NEW.transaction_id, OLD.transaction_id),
        CASE WHEN TG_OP = 'INSERT' THEN 'I' WHEN TG_OP = 'UPDATE' THEN 'U' ELSE 'D' END,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE '{}'::jsonb END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE '{}'::jsonb END,
        current_user,
        now()
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_transaction_audit
AFTER INSERT OR UPDATE OR DELETE ON app.transaction
FOR EACH ROW
EXECUTE FUNCTION audit.trigger_transaction_audit();

COMMIT;

--индексация

SET ROLE app_owner;

-- app.employee
CREATE INDEX ix_employee_branch ON app.employee(branch_id);

-- app.customer
CREATE INDEX ix_customer_employee ON app.customer(employee_id);
CREATE INDEX ix_customer_branch ON app.customer(branch_id);
CREATE INDEX ix_customer_searchClient ON app.customer(last_name, first_name);

-- app.account
CREATE INDEX ix_account_customer ON app.account(customer_id);

-- app.card
CREATE INDEX ix_card_account ON app.card(account_id);

-- app.transaction
CREATE INDEX ix_transaction_source_account ON app.transaction(source_account_id);
CREATE INDEX ix_transaction_target_account ON app.transaction(target_account_id);
CREATE INDEX ix_transaction_created_at ON app.transaction(created_at);
CREATE INDEX ix_transaction_type ON app.transaction(transaction_type_id);

-- app.fraund_alert
CREATE INDEX ix_fraud_alert_transaction ON app.fraund_alert(transaction_id);
CREATE INDEX ix_fraud_alert_reviewed_by ON app.fraund_alert(reviewed_by);
CREATE INDEX ix_fraud_alert_pending ON app.fraund_alert(created_at DESC)
    WHERE status = 'PENDING';

SET ROLE audit_owner;

-- audit.login_log
CREATE INDEX ix_login_log_employee ON audit.login_log(employee_id);
CREATE INDEX ix_login_log_time ON audit.login_log(login_time);

-- audit.transaction_audit
CREATE INDEX ix_transaction_audit_transaction ON audit.transaction_audit(transaction_id);
CREATE INDEX ix_transaction_audit_changed_at ON audit.transaction_audit(changed_at);

BEGIN;

SET LOCAL ROLE app_owner;

INSERT INTO ref.branch
    (branch_id, branch_code, branch_name, city, address, phone, is_active)
VALUES
    (1,  '01-1', 'Отделение Центральное', 'Москва', 'Российская Федерация, Москва, ул. Тверская, д. 1', '+74950000001', TRUE),
    (2,  '02-1', 'Отделение Северное', 'Санкт-Петербург', 'Российская Федерация, Санкт-Петербург, Невский пр., д. 2', '+78120000002', TRUE),
    (3,  '03-1', 'Отделение Казанское', 'Казань', 'Российская Федерация, Казань, ул. Баумана, д. 3', '+78430000003', TRUE),
    (4,  '04-1', 'Отделение Уральское', 'Екатеринбург', 'Российская Федерация, Екатеринбург, ул. Ленина, д. 4', '+73430000004', TRUE),
    (5,  '05-1', 'Отделение Сибирское', 'Новосибирск', 'Российская Федерация, Новосибирск, Красный пр., д. 5', '+73830000005', TRUE),
    (6,  '06-1', 'Отделение Южное', 'Ростов-на-Дону', 'Российская Федерация, Ростов-на-Дону, ул. Большая Садовая, д. 6', '+78630000006', TRUE),
    (7,  '07-1', 'Отделение Поволжское', 'Самара', 'Российская Федерация, Самара, ул. Молодогвардейская, д. 7', '+78460000007', TRUE),
    (8,  '08-1', 'Отделение Приморское', 'Владивосток', 'Российская Федерация, Владивосток, ул. Светланская, д. 8', '+74230000008', TRUE),
    (9,  '09-1', 'Отделение Черноземное', 'Воронеж', 'Российская Федерация, Воронеж, пр. Революции, д. 9', '+74730000009', TRUE),
    (10, '10-1', 'Отделение Калининградское', 'Калининград', 'Российская Федерация, Калининград, Ленинский пр., д. 10', '+74010000010', TRUE);

INSERT INTO ref.currency (currency_code, currency_name, minor_units, is_active)
VALUES
    ('RUB', 'Российский рубль', 2, TRUE),
    ('USD', 'Доллар США', 2, TRUE),
    ('EUR', 'Евро', 2, TRUE),
    ('GBP', 'Фунт стерлингов', 2, TRUE),
    ('CNY', 'Китайский юань', 2, TRUE),
    ('JPY', 'Японская иена', 0, TRUE),
    ('CHF', 'Швейцарский франк', 2, TRUE),
    ('KZT', 'Казахстанский тенге', 2, TRUE),
    ('BYN', 'Белорусский рубль', 2, TRUE),
    ('INR', 'Индийская рупия', 2, TRUE);

INSERT INTO ref.transaction_type
    (transaction_type_id, type_name, daily_limit, requires_2fa, fraund_check_level)
VALUES
    (1, 'Перевод между счетами', 20, TRUE, 2),
    (2, 'Оплата покупки', 30, TRUE, 1),
    (3, 'Снятие наличных', 10, TRUE, 3),
    (4, 'Пополнение счета', 20, FALSE, 1),
    (5, 'Коммунальный платеж', 10, TRUE, 1),
    (6, 'Международный перевод', 5, TRUE, 3),
    (7, 'Возврат средств', 10, TRUE, 2),
    (8, 'Комиссия банка', 30, FALSE, 1),
    (9, 'Зачисление зарплаты', 5, FALSE, 1),
    (10, 'Блокировка операции', 10, TRUE, 3);

INSERT INTO app.employee
    (employee_id, branch_id, db_username, last_name, first_name, job_title, access_role, is_active)
VALUES
    (1, 1, 'employee01', 'Иванов', 'Иван', 'Оператор', 'app_writer', TRUE),
    (2, 2, 'employee02', 'Петров', 'Петр', 'Оператор', 'app_writer', TRUE),
    (3, 3, 'employee03', 'Сидорова', 'Анна', 'Менеджер', 'app_writer', TRUE),
    (4, 4, 'employee04', 'Кузнецов', 'Олег', 'Менеджер', 'app_writer', TRUE),
    (5, 5, 'employee05', 'Смирнова', 'Елена', 'Специалист KYC', 'app_writer', TRUE),
    (6, 6, 'employee06', 'Попов', 'Дмитрий', 'Специалист антифрода', 'app_writer', TRUE),
    (7, 7, 'employee07', 'Васильева', 'Мария', 'Оператор', 'app_reader', TRUE),
    (8, 8, 'employee08', 'Михайлов', 'Алексей', 'Аудитор', 'auditor', TRUE),
    (9, 9, 'employee09', 'Федорова', 'Ольга', 'Администратор БД', 'ddl_admin', TRUE),
    (10, 10, 'employee10', 'Николаев', 'Сергей', 'Специалист безопасности', 'security_admin', TRUE);

INSERT INTO app.customer
    (customer_id, employee_id, branch_id, last_name, first_name, middle_name,
     birth_date, passport_enc, tax_id_enc, tax_id_hash, email, phone, kyc_status)
VALUES
    (1, 1, 1, 'Алексеев', 'Артем', 'Игоревич', DATE '1985-03-12',
     pgp_sym_encrypt('DEMO-PASSPORT-0001', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0001', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0001', 'sha256'),
     'client01@example.com', '+79990000001', 'VERIFIED'),
    (2, 2, 2, 'Борисова', 'Ирина', 'Павловна', DATE '1990-07-24',
     pgp_sym_encrypt('DEMO-PASSPORT-0002', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0002', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0002', 'sha256'),
     'client02@example.com', '+79990000002', 'VERIFIED'),
    (3, 3, 3, 'Волков', 'Максим', 'Андреевич', DATE '1978-11-05',
     pgp_sym_encrypt('DEMO-PASSPORT-0003', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0003', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0003', 'sha256'),
     'client03@example.com', '+79990000003', 'VERIFIED'),
    (4, 4, 4, 'Григорьева', 'Наталья', 'Сергеевна', DATE '1995-01-17',
     pgp_sym_encrypt('DEMO-PASSPORT-0004', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0004', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0004', 'sha256'),
     'client04@example.com', '+79990000004', 'VERIFIED'),
    (5, 5, 5, 'Данилов', 'Кирилл', 'Олегович', DATE '1988-09-30',
     pgp_sym_encrypt('DEMO-PASSPORT-0005', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0005', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0005', 'sha256'),
     'client05@example.com', '+79990000005', 'VERIFIED'),
    (6, 6, 6, 'Егорова', 'Татьяна', 'Ильинична', DATE '1982-04-08',
     pgp_sym_encrypt('DEMO-PASSPORT-0006', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0006', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0006', 'sha256'),
     'client06@example.com', '+79990000006', 'VERIFIED'),
    (7, 7, 7, 'Жуков', 'Роман', 'Викторович', DATE '2000-06-19',
     pgp_sym_encrypt('DEMO-PASSPORT-0007', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0007', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0007', 'sha256'),
     'client07@example.com', '+79990000007', 'ABSENT'),
    (8, 8, 8, 'Зайцева', 'Полина', 'Денисовна', DATE '1993-12-02',
     pgp_sym_encrypt('DEMO-PASSPORT-0008', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0008', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0008', 'sha256'),
     'client08@example.com', '+79990000008', 'REJECTED'),
    (9, 9, 9, 'Крылов', 'Владимир', 'Михайлович', DATE '1975-08-14',
     pgp_sym_encrypt('DEMO-PASSPORT-0009', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0009', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0009', 'sha256'),
     'client09@example.com', '+79990000009', 'VERIFIED'),
    (10, 10, 10, 'Лебедева', 'Софья', 'Алексеевна', DATE '1998-02-27',
     pgp_sym_encrypt('DEMO-PASSPORT-0010', 'DEMO_ENCRYPTION_KEY'),
     pgp_sym_encrypt('DEMO-TAX-0010', 'DEMO_ENCRYPTION_KEY'), digest('DEMO-TAX-0010', 'sha256'),
     'client10@example.com', '+79990000010', 'BLOCKED');

INSERT INTO app.account
    (account_id, customer_id, currency_code, account_number, balance, overdraft_limit, status)
VALUES
    (1, 1, 'RUB', '40817810000000000001', 12500.000, 0.00, 'ACTIVE'),
    (2, 2, 'RUB', '40817810000000000002', 8200.500, 0.00, 'ACTIVE'),
    (3, 3, 'RUB', '40817810000000000003', 56000.000, 5000.00, 'ACTIVE'),
    (4, 4, 'RUB', '40817810000000000004', 900.250, 0.00, 'ACTIVE'),
    (5, 5, 'RUB', '40817810000000000005', 23000.000, 0.00, 'ACTIVE'),
    (6, 6, 'RUB', '40817810000000000006', 17800.750, 1000.00, 'ACTIVE'),
    (7, 7, 'RUB', '40817810000000000007', 0.000, 0.00, 'FROZEN'),
    (8, 8, 'RUB', '40817810000000000008', 4400.000, 0.00, 'ACTIVE'),
    (9, 9, 'RUB', '40817810000000000009', 75000.000, 10000.00, 'ACTIVE'),
    (10, 10, 'RUB', '40817810000000000010', 3100.000, 0.00, 'ACTIVE');

INSERT INTO app.card
    (card_id, account_id, pan_token, pan_token_enc, holder_name, expiry_month, expiry_year, status)
VALUES
    (1, 1, 'tok_demo_0001', pgp_sym_encrypt('tok_demo_0001', 'DEMO_ENCRYPTION_KEY'), 'ARTEM ALEKSEEV', 12, 2028, 'ACTIVE'),
    (2, 2, 'tok_demo_0002', pgp_sym_encrypt('tok_demo_0002', 'DEMO_ENCRYPTION_KEY'), 'IRINA BORISOVA', 11, 2027, 'ACTIVE'),
    (3, 3, 'tok_demo_0003', pgp_sym_encrypt('tok_demo_0003', 'DEMO_ENCRYPTION_KEY'), 'MAXIM VOLKOV', 10, 2029, 'ACTIVE'),
    (4, 4, 'tok_demo_0004', pgp_sym_encrypt('tok_demo_0004', 'DEMO_ENCRYPTION_KEY'), 'NATALIA GRIGORIEVA', 9, 2028, 'ACTIVE'),
    (5, 5, 'tok_demo_0005', pgp_sym_encrypt('tok_demo_0005', 'DEMO_ENCRYPTION_KEY'), 'KIRILL DANILOV', 8, 2027, 'ACTIVE'),
    (6, 6, 'tok_demo_0006', pgp_sym_encrypt('tok_demo_0006', 'DEMO_ENCRYPTION_KEY'), 'TATIANA EGOROVA', 7, 2029, 'ACTIVE'),
    (7, 7, 'tok_demo_0007', pgp_sym_encrypt('tok_demo_0007', 'DEMO_ENCRYPTION_KEY'), 'ROMAN ZHUKOV', 6, 2028, 'BLOCKED'),
    (8, 8, 'tok_demo_0008', pgp_sym_encrypt('tok_demo_0008', 'DEMO_ENCRYPTION_KEY'), 'POLINA ZAITSEVA', 5, 2027, 'ACTIVE'),
    (9, 9, 'tok_demo_0009', pgp_sym_encrypt('tok_demo_0009', 'DEMO_ENCRYPTION_KEY'), 'VLADIMIR KRYLOV', 4, 2029, 'ACTIVE'),
    (10, 10, 'tok_demo_0010', pgp_sym_encrypt('tok_demo_0010', 'DEMO_ENCRYPTION_KEY'), 'SOFIA LEBEDEVA', 3, 2028, 'ACTIVE');

INSERT INTO app.transaction
    (transaction_id, transaction_type_id, source_account_id, target_account_id,
     currency_code, amount, description, status, completed_at)
VALUES
    (1, 1, 1, 2, 'RUB', 500.000, 'Демонстрационный перевод 1', 'COMPLETED', now()),
    (2, 2, 2, 3, 'RUB', 1200.000, 'Демонстрационная покупка 2', 'COMPLETED', now()),
    (3, 3, 3, 4, 'RUB', 3000.000, 'Демонстрационное снятие 3', 'COMPLETED', now()),
    (4, 4, 4, 5, 'RUB', 2500.000, 'Демонстрационное пополнение 4', 'COMPLETED', now()),
    (5, 5, 5, 6, 'RUB', 1800.000, 'Демонстрационный платеж 5', 'COMPLETED', now()),
    (6, 6, 6, 7, 'RUB', 750.000, 'Демонстрационный перевод 6', 'COMPLETED', now()),
    (7, 7, 7, 8, 'RUB', 400.000, 'Демонстрационный возврат 7', 'COMPLETED', now()),
    (8, 8, 8, 9, 'RUB', 150.000, 'Демонстрационная комиссия 8', 'COMPLETED', now()),
    (9, 9, 9, 10, 'RUB', 45000.000, 'Демонстрационное зачисление 9', 'COMPLETED', now()),
    (10, 10, 10, 1, 'RUB', 999.000, 'Демонстрационная проверка 10', 'REJECTED', now());

INSERT INTO app.auth_credential
    (credential_id, customer_id, login, password_hash, mfa_secret_enc, failed_attempts, last_login_at)
VALUES
    (1, 1, 'client_login_01', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0001', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (2, 2, 'client_login_02', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0002', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (3, 3, 'client_login_03', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0003', 'DEMO_ENCRYPTION_KEY'), 1, now()),
    (4, 4, 'client_login_04', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0004', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (5, 5, 'client_login_05', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0005', 'DEMO_ENCRYPTION_KEY'), 2, now()),
    (6, 6, 'client_login_06', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0006', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (7, 7, 'client_login_07', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0007', 'DEMO_ENCRYPTION_KEY'), 3, now()),
    (8, 8, 'client_login_08', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0008', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (9, 9, 'client_login_09', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0009', 'DEMO_ENCRYPTION_KEY'), 0, now()),
    (10, 10, 'client_login_10', '$2b$12$DEMO_HASH_NOT_FOR_AUTHENTICATION_000000000000000000000', pgp_sym_encrypt('DEMO-MFA-0010', 'DEMO_ENCRYPTION_KEY'), 5, now());

INSERT INTO app.fraund_alert
    (alert_id, transaction_id, reviewed_by, rule_code, risk_score, status, resolved_at)
VALUES
    (1, 1, 6, 'VELOCITY_CHECK', 20, 'FALSE_POSITIVE', now()),
    (2, 2, 6, 'UNUSUAL_MERCHANT', 35, 'FALSE_POSITIVE', now()),
    (3, 3, 6, 'CASH_WITHDRAWAL_LIMIT', 75, 'TRUE_POSITIVE', now()),
    (4, 4, 6, 'ACCOUNT_ACTIVITY', 15, 'FALSE_POSITIVE', now()),
    (5, 5, 6, 'UNUSUAL_AMOUNT', 45, 'FALSE_POSITIVE', now()),
    (6, 6, 6, 'NEW_BENEFICIARY', 60, 'PENDING', NULL),
    (7, 7, 6, 'REFUND_PATTERN', 25, 'FALSE_POSITIVE', now()),
    (8, 8, 6, 'FREQUENT_FEES', 10, 'FALSE_POSITIVE', now()),
    (9, 9, 6, 'HIGH_VALUE_TRANSFER', 90, 'TRUE_POSITIVE', now()),
    (10, 10, 6, 'DECLINED_OPERATION', 55, 'PENDING', NULL);

-- Синхронизация последовательностей после вставки явных ID.
SELECT setval(pg_get_serial_sequence('app.employee', 'employee_id'), (SELECT MAX(employee_id) FROM app.employee));
SELECT setval(pg_get_serial_sequence('app.customer', 'customer_id'), (SELECT MAX(customer_id) FROM app.customer));
SELECT setval(pg_get_serial_sequence('app.account', 'account_id'), (SELECT MAX(account_id) FROM app.account));
SELECT setval(pg_get_serial_sequence('app.card', 'card_id'), (SELECT MAX(card_id) FROM app.card));
SELECT setval(pg_get_serial_sequence('app.transaction', 'transaction_id'), (SELECT MAX(transaction_id) FROM app.transaction));
SELECT setval(pg_get_serial_sequence('app.auth_credential', 'credential_id'), (SELECT MAX(credential_id) FROM app.auth_credential));
SELECT setval(pg_get_serial_sequence('app.fraund_alert', 'alert_id'), (SELECT MAX(alert_id) FROM app.fraund_alert));

COMMIT;

RESET ROLE;


-- РОЛИ И ПРИВИЛЕГИИ

-- Отзываем права PUBLIC.
REVOKE ALL ON DATABASE "first_lab" FROM PUBLIC;
GRANT CONNECT ON DATABASE "first_lab"
    TO app_reader, app_writer, auditor, ddl_admin, dml_admin, security_admin, app_owner;

-- Не разрешаем PUBLIC создавать объекты в стандартной схеме.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Отзываем права PUBLIC на схемы и существующие объекты.
REVOKE ALL ON SCHEMA ref, app, audit, stg FROM PUBLIC;
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA ref, app, audit, stg FROM PUBLIC, ddl_admin;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA ref, app, audit, stg FROM PUBLIC, ddl_admin;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, app, audit, stg FROM PUBLIC, ddl_admin;

-- Доступ к схемам.
GRANT USAGE ON SCHEMA ref TO app_reader, app_writer;
GRANT USAGE ON SCHEMA app TO app_reader, app_writer, audit_owner;
GRANT USAGE ON SCHEMA audit TO auditor;
GRANT USAGE ON SCHEMA stg TO dml_admin;

-- DDL-администратор может создавать объекты в схемах.
GRANT USAGE, CREATE ON SCHEMA app, ref, audit, stg TO ddl_admin;

GRANT SELECT
    ON ALL TABLES IN SCHEMA app,ref TO app_reader;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA ref, app TO app_writer;
-- Аудитор только читает журналы.
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO auditor;

GRANT USAGE ON SCHEMA ref, app, audit, stg TO dml_admin;
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA ref, app, audit, stg TO dml_admin;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_writer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA ref, app, audit, stg TO dml_admin;



-- Новые таблицы app: права writer.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_writer;

-- Новые последовательности app.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA app
    GRANT USAGE ON SEQUENCES TO app_writer;

-- Новые таблицы ref: справочники доступны на чтение.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA ref
    GRANT SELECT ON TABLES TO app_reader, app_writer;

-- Новые журналы доступны аудитору только на чтение.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA audit
    GRANT SELECT ON TABLES TO auditor;

-- Новые таблицы и последовательности stg для DML-администратора.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA stg
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dml_admin;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA stg
    GRANT USAGE ON SEQUENCES TO dml_admin;

-- Запрет привилегий по умолчанию для PUBLIC.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner
    REVOKE ALL ON TABLES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner
    REVOKE ALL ON SEQUENCES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE app_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

BEGIN;


CREATE ROLE lab_reader
    LOGIN
    PASSWORD 'lab_reader'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

CREATE ROLE lab_writer
    LOGIN
    PASSWORD 'lab_writer'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

CREATE ROLE lab_auditor
    LOGIN
    PASSWORD 'lab_auditor'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

CREATE ROLE lab_ddl_admin
    LOGIN
    PASSWORD 'lab_ddl_admin'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

CREATE ROLE lab_dml_admin
    LOGIN
    PASSWORD 'lab_dml_admin'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

CREATE ROLE lab_security_admin
    LOGIN
    PASSWORD 'lab_security_admin'
    NOINHERIT
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOREPLICATION
    NOBYPASSRLS
    CONNECTION LIMIT 10;

GRANT app_reader
TO lab_reader
WITH INHERIT TRUE, SET FALSE;

GRANT app_writer
TO lab_writer
WITH INHERIT TRUE, SET FALSE;

GRANT auditor
TO lab_auditor
WITH INHERIT TRUE, SET FALSE;

GRANT ddl_admin
TO lab_ddl_admin
WITH INHERIT TRUE, SET FALSE;

GRANT dml_admin
TO lab_dml_admin
WITH INHERIT TRUE, SET TRUE;

GRANT security_admin
TO lab_security_admin
WITH INHERIT TRUE, SET TRUE;


REVOKE ALL
ON DATABASE "first_lab"
FROM PUBLIC;

GRANT CONNECT
ON DATABASE "first_lab"
TO
    lab_reader,
    lab_writer,
    lab_auditor,
    lab_ddl_admin,
    lab_dml_admin,
    lab_security_admin;
COMMIT;
