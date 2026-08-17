/*=========================================================
Project : Online Retail Sales Analytics
Layer   : Data Warehouse / Star Schema
Input   : analytics_online_retail
Output  : dim_date, dim_product, dim_customer, dim_country, fact_sales

Purpose 
- Build the star schema by creating reusable dimension tables for date, product, customer, and country.
- Create the fact_sales table at the invoice-line-item grain and link each transaction to its corresponding dimension keys.
- Handle missing dimension references through 'UNKNOWN' records and validate key mappings before loading the fact table.
- Perform post-load data quality, revenue reconciliation, star schema sanity checks, and create indexes to support analytical queries.

=========================================================*/
USE online_retail_analytics; 

DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_date;

-- 1. CREATE dim_date DIMENSION TABLE --
CREATE TABLE dim_date (
	date_key INT PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    calendar_year SMALLINT NOT NULL,
    calendar_quarter TINYINT NOT NULL,
    calendar_month TINYINT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    week_of_year TINYINT NOT NULL,
    day_of_month TINYINT NOT NULL,
    day_name VARCHAR(20) NOT NULL,
    day_of_week TINYINT NOT NULL,
    is_weekend TINYINT NOT NULL
);

INSERT INTO dim_date (
	date_key,
    full_date,
    calendar_year,
    calendar_quarter,
    calendar_month,
    month_name,
    week_of_year,
    day_of_month,
    day_name,
    day_of_week,
    is_weekend
)

SELECT DISTINCT 
	CAST(DATE_FORMAT(invoice_date_only, '%Y%m%d') AS UNSIGNED)
		AS date_key,
        
	invoice_date_only AS full_date,
    YEAR(invoice_date_only) AS calendar_year,
    QUARTER(invoice_date_only) AS calendar_month,
    MONTH(invoice_date_only) AS calendar_month,
    MONTHNAME(invoice_date_only) AS month_name,
    WEEK(invoice_date_only, 3) AS week_of_year,
    DAY(invoice_date_only) AS day_of_month,
    DAYNAME(invoice_date_only) AS day_name,
    DAYOFWEEK(invoice_date_only) AS day_of_week,
    
    CASE 
		WHEN DAYOFWEEK(invoice_date_only) IN (1,7) -- 7 is Saturday, 1 is Sunday --
        THEN 1
        ELSE 0
	END AS is_weekend
FROM analytics_online_retail
WHERE invoice_date_only IS NOT NULL;

SELECT *
FROM dim_date
ORDER BY full_date
LIMIT 20;

-- 2. CREATE dim_product DIMENSION TABLE --
SELECT 
	stock_code,
	COUNT(DISTINCT product_description) AS description_count
FROM analytics_online_retail
WHERE stock_code IS NOT NULL
GROUP BY stock_code
HAVING COUNT(DISTINCT product_description) > 1
ORDER BY description_count DESC 
LIMIT 20;

DROP TABLE IF EXISTS dim_product;
CREATE TABLE dim_product (
	product_key INT AUTO_INCREMENT PRIMARY KEY,
    stock_code VARCHAR(30),
    product_description VARCHAR(255),
    UNIQUE KEY uq_dim_product_stock_code (stock_code)
);

INSERT INTO dim_product (
	stock_code,
    product_description
)
VALUES (
	'UNKNOWN',
    'Unknown Product'
);
/*
Create the Product Dimension table by selecting one representative description
for each stock_code. If multiple descriptions exist, keep the most frequently
used one. Also insert an 'Unknown Product' record to handle missing or invalid
product references.
*/
INSERT INTO dim_product (
    stock_code,
    product_description
)
WITH description_frequency AS (
    SELECT
        stock_code,
        product_description,
        COUNT(*) AS usage_count
    FROM analytics_online_retail
    WHERE stock_code IS NOT NULL
    GROUP BY
        stock_code,
        product_description
),

ranked_descriptions AS (
    SELECT
        stock_code,
        product_description,
        usage_count,

        ROW_NUMBER() OVER (
            PARTITION BY stock_code
            ORDER BY
                usage_count DESC,
                product_description
        ) AS description_rank

    FROM description_frequency
)

SELECT
    stock_code,
    COALESCE(product_description, 'Description Unavailable')
FROM ranked_descriptions
WHERE description_rank = 1;
-- 3958 rows + 1 unknown row --

-- POST CHECK -- 
SELECT * 
FROM dim_product
LIMIT 20;

SELECT
    COUNT(*) AS total_products,
    COUNT(DISTINCT stock_code) AS unique_stock_codes
FROM dim_product;

-- 3. CREATE dim_customer DIMENSION TABLE --
DROP TABLE IF EXISTS dim_customer;

CREATE TABLE dim_customer (
    customer_key INT AUTO_INCREMENT PRIMARY KEY,
    customer_id VARCHAR(20),
    UNIQUE KEY uq_dim_customer_customer_id (customer_id)
);

INSERT INTO dim_customer (
    customer_id
)
VALUES (
    'UNKNOWN'
);

INSERT INTO dim_customer (
    customer_id
)
SELECT DISTINCT
    customer_id
FROM analytics_online_retail
WHERE customer_id IS NOT NULL
ORDER BY customer_id;

-- POST CHECK -- 
SELECT COUNT(*) AS total_customers
FROM dim_customer;

SELECT COUNT(DISTINCT customer_id) AS analytics_customers
FROM analytics_online_retail
WHERE customer_id IS NOT NULL;

-- 4. CREATE dim_country DIMENSION TABLE -- 
DROP TABLE IF EXISTS dim_country;

CREATE TABLE dim_country (
	country_key INT AUTO_INCREMENT PRIMARY KEY,
    country_name VARCHAR(100),
    UNIQUE KEY uq_dim_country_name (country_name)
);

INSERT INTO dim_country (
	country_name
)
VALUES (
	'Unknown'
);

INSERT INTO dim_country (
	country_name
)
SELECT DISTINCT
	country
FROM analytics_online_retail
WHERE country IS NOT NULL
ORDER BY country;

-- POST CHECK --
SELECT COUNT(*) 
FROM dim_country 
ORDER BY country_key;

SELECT COUNT(DISTINCT country) AS analytics_country
FROM analytics_online_retail
WHERE country IS NOT NULL;

-- 5. CREATE fact_sales TABLE -- 
-- Grain: One invoice line item (stock code) per invoice.--
CREATE TABLE fact_sales (
    sales_key BIGINT AUTO_INCREMENT PRIMARY KEY,

    source_analytics_id BIGINT NOT NULL,

    date_key INT NOT NULL,
    product_key INT NOT NULL,
    customer_key INT NOT NULL,
    country_key INT NOT NULL,

    invoice_no VARCHAR(20),
    invoice_datetime DATETIME,
    sales_hour TINYINT,

    quantity INT,
    unit_price DECIMAL(12,4),

    transaction_status VARCHAR(20),
    data_quality_flag VARCHAR(100),

    transaction_value DECIMAL(18,4),
    completed_revenue DECIMAL(18,4),
    cancelled_value DECIMAL(18,4),
    adjustment_value DECIMAL(18,4),
    net_revenue DECIMAL(18,4),

    is_completed TINYINT,
    is_cancelled TINYINT,
    is_adjustment TINYINT,
    is_review TINYINT,
    has_customer_id TINYINT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_fact_date
        FOREIGN KEY (date_key)
        REFERENCES dim_date(date_key),

    CONSTRAINT fk_fact_product
        FOREIGN KEY (product_key)
        REFERENCES dim_product(product_key),

    CONSTRAINT fk_fact_customer
        FOREIGN KEY (customer_key)
        REFERENCES dim_customer(customer_key),

    CONSTRAINT fk_fact_country
        FOREIGN KEY (country_key)
        REFERENCES dim_country(country_key)
);

-- Before inserting values, check to see if dimension keys are found --
SELECT
    a.analytics_id,
    a.invoice_no,

    d.date_key,
    p.product_key,
    c.customer_key,
    co.country_key,

    a.quantity,
    a.unit_price,
    a.transaction_value

FROM analytics_online_retail AS a

LEFT JOIN dim_date AS d
    ON a.invoice_date_only = d.full_date

LEFT JOIN dim_product AS p
    ON a.stock_code = p.stock_code

LEFT JOIN dim_customer AS c
    ON COALESCE(a.customer_id, 'UNKNOWN') = c.customer_id

LEFT JOIN dim_country AS co
    ON COALESCE(a.country, 'Unknown') = co.country_name

LIMIT 100;

-- Check to see if any key is NULL --
SELECT
    SUM(d.date_key IS NULL) AS missing_date_keys,
    SUM(p.product_key IS NULL) AS missing_product_keys,
    SUM(c.customer_key IS NULL) AS missing_customer_keys,
    SUM(co.country_key IS NULL) AS missing_country_keys

FROM analytics_online_retail AS a

LEFT JOIN dim_date AS d
    ON a.invoice_date_only = d.full_date

LEFT JOIN dim_product AS p
    ON a.stock_code = p.stock_code

LEFT JOIN dim_customer AS c
    ON COALESCE(a.customer_id, 'UNKNOWN') = c.customer_id

LEFT JOIN dim_country AS co
    ON COALESCE(a.country, 'Unknown') = co.country_name;
    
    
-- Inserting values -- 
INSERT INTO fact_sales (
    source_analytics_id,

    date_key,
    product_key,
    customer_key,
    country_key,

    invoice_no,
    invoice_datetime,
    sales_hour,

    quantity,
    unit_price,

    transaction_status,
    data_quality_flag,

    transaction_value,
    completed_revenue,
    cancelled_value,
    adjustment_value,
    net_revenue,

    is_completed,
    is_cancelled,
    is_adjustment,
    is_review,
    has_customer_id
)

SELECT
    a.analytics_id AS source_analytics_id,

    d.date_key,
    p.product_key,
    c.customer_key,
    co.country_key,

    a.invoice_no,
    a.invoice_date,
    a.sales_hour,

    a.quantity,
    a.unit_price,

    a.transaction_status,
    a.data_quality_flag,

    a.transaction_value,
    a.completed_revenue,
    a.cancelled_value,
    a.adjustment_value,
    a.net_revenue,

    a.is_completed,
    a.is_cancelled,
    a.is_adjustment,
    a.is_review,
    a.has_customer_id

FROM analytics_online_retail AS a

INNER JOIN dim_date AS d
    ON a.invoice_date_only = d.full_date

INNER JOIN dim_product AS p
    ON COALESCE(a.stock_code, 'UNKNOWN') = p.stock_code

INNER JOIN dim_customer AS c
    ON COALESCE(a.customer_id, 'UNKNOWN') = c.customer_id

INNER JOIN dim_country AS co
    ON COALESCE(a.country, 'Unknown') = co.country_name;
    
-- POST CHECK -- 
SELECT
    CASE
        WHEN
            (SELECT COUNT(*) FROM analytics_online_retail)
            =
            (SELECT COUNT(*) FROM fact_sales)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS fact_row_count_check;
    
    
-- 6. DATABASE SANITY CHECKS -- 
SELECT 
	'Analytics Layer' AS source_table,
    ROUND(SUM(transaction_value),2) AS transaction_value,
    ROUND(SUM(completed_revenue),2) AS completed_revenue,
    ROUND(SUM(cancelled_value),2) AS cancelled_value,
    ROUND(SUM(adjustment_value),2) AS adjustment_value,
    ROUND(SUM(net_revenue),2) AS net_revenue
FROM analytics_online_retail

UNION ALL

SELECT 
	'Fact Sales',
    ROUND(SUM(transaction_value),2),
    ROUND(SUM(completed_revenue),2),
    ROUND(SUM(cancelled_value),2),
    ROUND(SUM(adjustment_value),2),
    ROUND(SUM(net_revenue),2)
FROM fact_sales;

-- Check Star Schema -- 
-- Monthly revenue --
SELECT 
	d.calendar_year,
    d.calendar_month,
    d.month_name,
    ROUND(SUM(f.completed_revenue),2) AS completed_revenue,
    ROUND(SUM(f.cancelled_value),2) AS cancelled_value,
    ROUND(SUM(f.net_revenue),2) AS net_revenue
FROM fact_sales as f
JOIN dim_date as d 
	ON f.date_key = d.date_key
GROUP BY
	d.calendar_year,
    d.calendar_month,
    d.month_name
ORDER BY
	d.calendar_year,
    d.calendar_month;
    
-- Top products --
SELECT
	p.stock_code,
    p.product_description,
    SUM(
		CASE
			WHEN f.is_completed = 1
            THEN f.quantity
            ELSE 0
		END
	) AS units_sold,
    ROUND(SUM(f.completed_revenue),2) AS revenue
FROM fact_sales AS f
JOIN dim_product AS p
	ON f.product_key = p.product_key
GROUP BY 
	p.stock_code,
    p.product_description
ORDER BY revenue DESC
LIMIT 20;

-- 7. CREATE INDEXING FOR FACT TABLE --
CREATE INDEX idx_fact_invoice
ON fact_sales(invoice_no);

CREATE INDEX idx_fact_status
ON fact_sales(transaction_status);

CREATE INDEX idx_fact_date_status
ON fact_sales(date_key, transaction_status);

CREATE INDEX idx_fact_customer_date
ON fact_sales(customer_key, date_key);

CREATE INDEX idx_fact_product_date
ON fact_sales(product_key, date_key);

-- 8. ETL Audit Log -- 
INSERT INTO etl_audit_log (
    pipeline_step,
    source_rows,
    output_rows,
    rows_removed
)
SELECT
    'Create star schema and fact_sales',

    (SELECT COUNT(*)
     FROM analytics_online_retail),

    (SELECT COUNT(*)
     FROM fact_sales),

    (SELECT COUNT(*)
     FROM analytics_online_retail),

    (SELECT COUNT(*)
     FROM fact_sales);


	

