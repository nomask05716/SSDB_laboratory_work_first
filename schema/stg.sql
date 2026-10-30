CREATE SCHEMA IF NOT EXISTS stg;

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