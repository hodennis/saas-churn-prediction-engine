INSERT INTO accounts (account_id, industry, signup_date, current_mrr, status)
SELECT
    'ACCT_' || LPAD(i::text, 4, '0'),
    (ARRAY['Technology', 'Healthcare', 'Finance', 'Retail', 'Logistics'])[floor(random() * 5 + 1)],
    CURRENT_DATE - (random() * 365)::int,
    floor(random() * 5000 + 500),
    'Active'
FROM generate_series(1, 500) s(i);

UPDATE accounts
SET status = 'Churned'
WHERE account_id IN (
    SELECT account_id FROM accounts ORDER BY random() LIMIT 75
);

INSERT INTO account_telemetry (account_id, report_month, mrr_amount, total_logins_30d, active_users, features_used, support_tickets)
SELECT
    a.account_id,
    (DATE_TRUNC('month', CURRENT_DATE) - interval '1 month' * m.month_offset)::date,
    CASE
        WHEN a.status = 'Churned' AND m.month_offset = 0 THEN 0 -- Churned this month
        WHEN a.status = 'Churned' THEN a.current_mrr * (1 - (0.1 * (6 - m.month_offset))) -- Decaying MRR leading to churn
        ELSE a.current_mrr * (1 + (0.02 * (6 - m.month_offset))) -- Growing MRR for healthy accounts
    END,
    CASE
        WHEN a.status = 'Churned' AND m.month_offset <= 2 THEN floor(random() * 5) -- Critical Feature: Logins drop before churn
        ELSE floor(random() * 40 + 10) -- Healthy login baseline
    END,
    floor(random() * 10 + 2),
    floor(random() * 8 + 1),
    floor(random() * 3)
FROM accounts a
CROSS JOIN generate_series(0, 5) m(month_offset);
