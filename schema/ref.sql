CREATE SCHEMA IF NOT EXISTS ref;

--сущности данной схемы:
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