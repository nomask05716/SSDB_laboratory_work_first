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