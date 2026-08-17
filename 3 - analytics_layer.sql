/*=========================================================
Project : Online Retail Sales Analytics
Layer   : Analytics Layer
Input   : cleaned_online_retail
Output  : analytics_online_retail

Purpose:
- Create business-ready calculated fields
- Separate completed, cancelled and adjustment values
- Add time-based analytical features
- Create transaction and customer availability flags
- Prepare the dataset for dimensional modelling

Revenue rules:
- Completed revenue includes completed transactions only
- Cancelled and adjustment values are stored as positive values
- Net revenue retains negative transaction effects
- Review transactions are excluded from revenue calculations
=========================================================*/
USE online_retail_analytics;

SELECT 
	COUNT(*) AS cleaned_rows
FROM
	cleaned_online_retail;

-- PRE-CHECK -- 
SELECT
	transaction_status,
    COUNT(*) AS total_rows
FROM cleaned_online_retail
GROUP BY transaction_status
ORDER BY total_rows DESC;

-- CREATE analytics_online_retail TABLE--
DROP TABLE IF EXISTS analytics_online_retail;

CREATE TABLE analytics_online_retail (
	analytics_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    
    -- data lineage --
    source_cleaned_id BIGINT NOT NULL,
    source_staging_id BIGINT NOT NULL,
    
    invoice_no VARCHAR(20),
    stock_code VARCHAR(30),
    product_description VARCHAR(255),
    
    quantity INT,
    invoice_date DATETIME,
    invoice_date_only DATE,
    unit_price DECIMAL(12,4),
    
    customer_id VARCHAR(20),
    country VARCHAR(100),
    
    transaction_status VARCHAR(20),
    data_quality_flag VARCHAR(100),
    
    transaction_value DECIMAL(18,4),
    completed_revenue DECIMAL(18,4),
    cancelled_value DECIMAL(18,4),
    adjustment_value DECIMAL(18,4),
    net_revenue DECIMAL(18,4),
    
    sales_year SMALLINT,
    sales_quarter TINYINT,
    sales_month TINYINT,
    sales_month_name VARCHAR(20),
    sales_week TINYINT,
    sales_day TINYINT,
    sales_day_name VARCHAR(20),
    sales_hour TINYINT,
    is_weekend TINYINT,
    
    is_completed TINYINT,
    is_cancelled TINYINT,
    is_adjustment TINYINT,
    is_review TINYINT,
    has_customer_id TINYINT,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO analytics_online_retail (
    source_cleaned_id,
    source_staging_id,
    invoice_no,
    stock_code,
    product_description,
    quantity,
    invoice_date,
    invoice_date_only,
    unit_price,
    customer_id,
    country,
    transaction_status,
    data_quality_flag,
    transaction_value,
    completed_revenue,
    cancelled_value,
    adjustment_value,
    net_revenue,
    sales_year,
    sales_quarter,
    sales_month,
    sales_month_name,
    sales_week,
    sales_day,
    sales_day_name,
    sales_hour,
    is_weekend,
    is_completed,
    is_cancelled,
    is_adjustment,
    is_review,
    has_customer_id
)
SELECT
    cleaned_id,
    source_staging_id,
    invoice_no,
    stock_code,
    product_description,
    quantity,
    invoice_date,
    DATE(invoice_date),
    unit_price,
    customer_id,
    country,
    transaction_status,
    data_quality_flag,

    quantity * unit_price,

    CASE
        WHEN transaction_status = 'Completed'
        THEN quantity * unit_price
        ELSE 0
    END,

    CASE
        WHEN transaction_status = 'Cancelled'
        THEN ABS(quantity * unit_price)
        ELSE 0
    END,

    CASE
        WHEN transaction_status = 'Adjustment'
        THEN ABS(quantity * unit_price)
        ELSE 0
    END,

    CASE
        WHEN transaction_status IN (
            'Completed',
            'Cancelled'
        )
        THEN quantity * unit_price
        ELSE 0
    END,

    YEAR(invoice_date),
    QUARTER(invoice_date),
    MONTH(invoice_date),
    MONTHNAME(invoice_date),
    WEEK(invoice_date, 3),
    DAY(invoice_date),
    DAYNAME(invoice_date),
    HOUR(invoice_date),

    CASE
        WHEN DAYOFWEEK(invoice_date) IN (1, 7)
        THEN 1
        ELSE 0
    END,

    CASE WHEN transaction_status = 'Completed' THEN 1 ELSE 0 END,
    CASE WHEN transaction_status = 'Cancelled' THEN 1 ELSE 0 END,
    CASE WHEN transaction_status = 'Adjustment' THEN 1 ELSE 0 END,
    CASE WHEN transaction_status = 'Review' THEN 1 ELSE 0 END,
    CASE WHEN customer_id IS NOT NULL THEN 1 ELSE 0 END

FROM cleaned_online_retail;

-- POST CHECKS -- 
SELECT
    (SELECT COUNT(*)
     FROM cleaned_online_retail) AS cleaned_rows,

    (SELECT COUNT(*)
     FROM analytics_online_retail) AS analytics_rows;

-- Revenue checks -- 
SELECT
    ROUND(SUM(completed_revenue), 2) AS completed_revenue,
    ROUND(SUM(cancelled_value), 2) AS cancelled_value,
    ROUND(SUM(adjustment_value), 2) AS adjustment_value,
    ROUND(SUM(net_revenue), 2) AS net_revenue
FROM analytics_online_retail;

-- Transaction value checks -- 
SELECT
	COUNT(*) AS incorrect_rows
FROM analytics_online_retail
WHERE transaction_value <> quantity * unit_price;

-- Revenue checks based on status
SELECT 
	transaction_status,
    COUNT(*) AS total_rows,
    ROUND(SUM(transaction_value),2) AS transaction_value,
    ROUND(SUM(completed_revenue),2) AS completed_revenue,
    ROUND(SUM(cancelled_value),2) AS cancelled_value,
    ROUND(SUM(adjustment_value),2) AS adjustment_value,
    ROUND(SUM(net_revenue),2) AS net_revenue
FROM analytics_online_retail
GROUP BY transaction_status
ORDER BY total_rows DESC;

-- Time features checks --
SELECT
    invoice_date,
    invoice_date_only,
    sales_year,
    sales_quarter,
    sales_month,
    sales_month_name,
    sales_week,
    sales_day,
    sales_day_name,
    sales_hour,
    is_weekend
FROM analytics_online_retail
LIMIT 20;

-- Analytical flags checks --
SELECT
    SUM(is_completed) AS completed_rows,
    SUM(is_cancelled) AS cancelled_rows,
    SUM(is_adjustment) AS adjustment_rows,
    SUM(is_review) AS review_rows,
    COUNT(*) AS total_rows
FROM analytics_online_retail;

-- Customer flags checks -- 
SELECT
    has_customer_id,
    COUNT(*) AS total_rows
FROM analytics_online_retail
GROUP BY has_customer_id;

-- ADD INDEXING -- 
CREATE INDEX idx_analytics_invoice
ON analytics_online_retail(invoice_no);

CREATE INDEX idx_analytics_product
ON analytics_online_retail(stock_code);

CREATE INDEX idx_analytics_customer
ON analytics_online_retail(customer_id);

CREATE INDEX idx_analytics_date
ON analytics_online_retail(invoice_date_only);

CREATE INDEX idx_analytics_country
ON analytics_online_retail(country);

CREATE INDEX idx_analytics_status
ON analytics_online_retail(transaction_status);

CREATE INDEX idx_analytics_year_month
ON analytics_online_retail(sales_year, sales_month);

-- ETL AUDIT LOG -- 
INSERT INTO etl_audit_log (
    pipeline_step,
    source_rows,
    output_rows,
    rows_removed
)

SELECT
    'Removed "Adjustment" from net_revenue',

    (SELECT COUNT(*)
     FROM cleaned_online_retail),

    (SELECT COUNT(*)
     FROM analytics_online_retail),

    (SELECT COUNT(*)
     FROM cleaned_online_retail)
    -
    (SELECT COUNT(*)
     FROM analytics_online_retail);
     
SELECT *
FROM etl_audit_log;
