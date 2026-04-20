CREATE OR REPLACE VIEW v_mrr_trends AS
WITH mrr_calc AS (
    SELECT
        account_id,
        report_month,
        mrr_amount,
        total_logins_30d,
        -- Calculate the previous month's MRR for the same account
        LAG(mrr_amount, 1) OVER (PARTITION BY account_id ORDER BY report_month) as prev_month_mrr
    FROM account_telemetry
)
SELECT
    account_id,
    report_month,
    mrr_amount,
    total_logins_30d,
    COALESCE(mrr_amount - prev_month_mrr, 0) as mrr_delta,
    -- Categorize the revenue movement for BI visualization
    CASE
        WHEN prev_month_mrr IS NULL THEN 'New Logo'
        WHEN mrr_amount > prev_month_mrr THEN 'Expansion'
        WHEN mrr_amount < prev_month_mrr AND mrr_amount > 0 THEN 'Contraction'
        WHEN mrr_amount = 0 AND prev_month_mrr > 0 THEN 'Churn'
        ELSE 'Flat'
    END as mrr_category
FROM mrr_calc;
