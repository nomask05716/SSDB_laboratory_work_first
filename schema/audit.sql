CREATE SCHEMA IF NOT EXISTS audit;

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