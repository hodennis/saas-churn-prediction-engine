CREATE TABLE accounts (
    account_id VARCHAR(50) PRIMARY KEY,
    industry VARCHAR(100),
    signup_date DATE,
    current_mrr DECIMAL(10, 2),
    status VARCHAR(20)
);

CREATE TABLE account_telemetry (
    telemetry_id SERIAL PRIMARY KEY,
    account_id VARCHAR(50) REFERENCES accounts(account_id),
    report_month DATE,
    mrr_amount DECIMAL(10, 2),
    total_logins_30d INT,
    active_users INT,
    features_used INT,
    support_tickets INT
);

CREATE INDEX idx_telemetry_date ON account_telemetry(report_month);
CREATE INDEX idx_telemetry_account ON account_telemetry(account_id);
