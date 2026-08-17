/*=========================================================
Project : Online Retail Sales Analytics
Layer   : Clean Layer
Input   : staging_online_retail
Output  : cleaned_online_retail

Purpose:
- Standardise text values
- Convert blank values to NULL
- Remove exact duplicate records by retaining duplicate_rank = 1
- Classify transaction types
- Flag remaining data-quality issues

Business rules:
- Cancelled invoices begin with "C"
- Negative quantities without "C" are treated as adjustments
- Completed sales require positive quantity and unit price
- Missing customers are retained for sales-level analysis
=========================================================*/

CREATE DATABASE IF NOT EXISTS online_retail_analytics;
USE online_retail_analytics;
SELECT DATABASE();

CREATE TABLE staging_online_retail (
	staging_id BIGINT AUTO_INCREMENT PRIMARY KEY, 
    invoice_no VARCHAR(20),
    stock_code VARCHAR(30),
    description VARCHAR(255),
    quantity INT, 
    invoice_date DATETIME,
    unit_price DECIMAL(12,4),
    customer_id VARCHAR(20),
    country VARCHAR(100),
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DESCRIBE staging_online_retail;

SELECT COUNT(*) AS total_rows
FROM staging_online_retail; -- should be 0 -- 

-- importing files -- 
LOAD DATA LOCAL INFILE
'C:/Users/hdat2/Online-Retail-Analytics/data/staging/online_retail_staging.csv'
INTO TABLE staging_online_retail
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
invoice_no,
stock_code,
description,
quantity,
invoice_date,
unit_price,
customer_id,
country
);

SET GLOBAL local_infile = ON;
SHOW VARIABLES LIKE 'local_infile';

-- **IMPORTED RESULTS** 
-- Check the imported results

SELECT COUNT(*) AS imported_rows
FROM staging_online_retail;

SELECT * 
FROM staging_online_retail
LIMIT 10;

-- Check the date range
SELECT 
	MIN(invoice_date) AS earliest_transaction,
    MAX(invoice_date) AS latest_transaction
FROM staging_online_retail;

-- Check missing values
SELECT
    SUM(
        CASE
            WHEN customer_id IS NULL
              OR TRIM(customer_id) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_customer_id
FROM staging_online_retail;

SELECT
    SUM(
        CASE
            WHEN description IS NULL
              OR TRIM(description) = ''
            THEN 1
            ELSE 0
        END
    ) AS missing_description
FROM staging_online_retail;

/*
- Missing customer ids: 135,080 (matched)
- Missing description: 1,454 (matched)
*/

-- *EXTRACT, TRANSFORM AND LOAD* 

DESCRIBE staging_online_retail;
DROP TABLE IF EXISTS cleaned_online_retail;

-- Create a new table for this stage
CREATE TABLE cleaned_online_retail (
	cleaned_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    
    source_staging_id BIGINT NOT NULL,
    
    invoice_no VARCHAR(20),
    stock_code VARCHAR(30),
    product_description VARCHAR(255),
    
    quantity INT,
    invoice_date DATETIME,
    unit_price DECIMAL(12,4),
    
    customer_id VARCHAR(20),
    country VARCHAR(100),
    
    transaction_status VARCHAR(20),
    data_quality_flag VARCHAR(100),
    
    cleaned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- BUSINESS RULES
-- Standardise Common Table Expression 
WITH standardized_data AS (
	SELECT 
		staging_id,
        
        NULLIF(TRIM(invoice_no), '') AS invoice_no,
        NULLIF(TRIM(stock_code), '') AS stock_code,
        NULLIF(TRIM(description), '') AS product_description,

        quantity,
        invoice_date,
        unit_price,

        NULLIF(TRIM(customer_id), '') AS customer_id,
        NULLIF(TRIM(country), '') AS country
	FROM 
		staging_online_retail
)

SELECT *
FROM standardized_data
LIMIT 10;

-- Define exact duplicates
WITH standardized_data AS (
	SELECT
		staging_id,
        NULLIF(TRIM(invoice_no),'') AS invoice_no,
        NULLIF(TRIM(stock_code), '') AS stock_code,
        NULLIF(TRIM(description), '') AS product_description,
        quantity,
        invoice_date,
        unit_price,
        NULLIF(TRIM(customer_id), '') AS customer_id,
        NULLIF(TRIM(country), '') AS country
	FROM 
		staging_online_retail
),
ranked_data AS (
	SELECT 
		*,
		ROW_NUMBER() OVER (
			PARTITION BY 
				invoice_no,
                stock_code,
                product_description,
                quantity,
                invoice_date,
                unit_price,
                customer_id,
                country
			ORDER BY staging_id
            ) AS duplicate_rank
	FROM standardized_data
)
SELECT *
FROM 
	ranked_data
WHERE 
	duplicate_rank > 1
LIMIT 20; -- After this code, we can identify which invoice has exact duplicates over the 8 defined partitioned features.

-- COMPLETE SCRIPT --
INSERT INTO cleaned_online_retail (
    source_staging_id,
    invoice_no,
    stock_code,
    product_description,
    quantity,
    invoice_date,
    unit_price,
    customer_id,
    country,
    transaction_status,
    data_quality_flag
)

WITH standardized_data AS (
    SELECT
        staging_id,

        NULLIF(TRIM(invoice_no), '') AS invoice_no,
        NULLIF(TRIM(stock_code), '') AS stock_code,
        NULLIF(TRIM(description), '') AS product_description,

        quantity,
        invoice_date,
        unit_price,

        NULLIF(TRIM(customer_id), '') AS customer_id,
        NULLIF(TRIM(country), '') AS country

    FROM staging_online_retail
),

ranked_data AS (
    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY
                invoice_no,
                stock_code,
                product_description,
                quantity,
                invoice_date,
                unit_price,
                customer_id,
                country
            ORDER BY staging_id
        ) AS duplicate_rank

    FROM standardized_data
)

SELECT
    staging_id AS source_staging_id,

    invoice_no,
    stock_code,
    product_description,

    quantity,
    invoice_date,
    unit_price,

    customer_id,
    country,

    CASE
        WHEN invoice_no LIKE 'C%'
            THEN 'Cancelled'
        WHEN quantity < 0
            THEN 'Adjustment'
        WHEN quantity > 0
             AND unit_price > 0
            THEN 'Completed'
		ELSE 'Review'
    END AS transaction_status,
    
    CASE
        WHEN invoice_no IS NULL
            THEN 'Missing Invoice Number'

        WHEN stock_code IS NULL
            THEN 'Missing Stock Code'

        WHEN product_description IS NULL
            THEN 'Missing Description'

        WHEN customer_id IS NULL
            THEN 'Missing Customer ID'

        WHEN country IS NULL
            THEN 'Missing Country'

        WHEN unit_price < 0
            THEN 'Negative Unit Price'

        WHEN unit_price = 0
            THEN 'Zero Unit Price'

        WHEN quantity = 0
            THEN 'Zero Quantity'

        ELSE 'Valid'
    END AS data_quality_flag

FROM ranked_data
WHERE duplicate_rank = 1; 
    
SELECT COUNT(*) AS cleaned_rows
FROM cleaned_online_retail;

-- ** POST-TRANSFORM CHECKS **
-- Checking transaction status
SELECT 
	transaction_status,
    COUNT(*) AS total_rows,
    ROUND(
		COUNT(*) * 100.0/
        SUM(COUNT(*)) OVER(),
        2
	) AS percentage
FROM cleaned_online_retail
GROUP BY transaction_status
ORDER BY total_rows DESC;

-- Checking data-quality flags
SELECT 
	data_quality_flag,
    COUNT(*) AS total_rows
FROM 
	cleaned_online_retail
GROUP BY 
	data_quality_flag
ORDER BY 
	total_rows DESC;

-- Checking transformed Customer IDs
SELECT 
	COUNT(*) AS missing_customer_ids
FROM 
	cleaned_online_retail
WHERE
	customer_id IS NULL;
    
-- Checking solved duplicates
SELECT 
	invoice_no,
    stock_code,
    product_description,
    quantity,
    invoice_date,
    unit_price,
    customer_id,
    country,
    COUNT(*) AS 'row_count'
FROM cleaned_online_retail
GROUP BY 
	invoice_no,
    stock_code,
    product_description,
    quantity,
    invoice_date,
    unit_price,
    customer_id,
    country
HAVING COUNT(*) > 1; -- If 0 rows occur, then exact duplicates are removed.

-- ** CREATE INDEXING ** -- 
CREATE INDEX idx_cleaned_invoice
ON cleaned_online_retail(invoice_no);

CREATE INDEX idx_cleaned_stock
ON cleaned_online_retail(stock_code);

CREATE INDEX idx_cleaned_customer
ON cleaned_online_retail(customer_id);

CREATE INDEX idx_cleaned_date
ON cleaned_online_retail(invoice_date);

CREATE INDEX idx_cleaned_country
ON cleaned_online_retail(country);

CREATE INDEX idx_cleaned_status
ON cleaned_online_retail(transaction_status);

-- ** CREATE AUDIT TABLE ** -- 
CREATE TABLE IF NOT EXISTS etl_audit_log (
    audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    pipeline_step VARCHAR(100),
    source_rows BIGINT,
    output_rows BIGINT,
    rows_removed BIGINT,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO etl_audit_log (
    pipeline_step,
    source_rows,
    output_rows,
    rows_removed
)

SELECT
    'Create cleaned_online_retail',

    (SELECT COUNT(*)
     FROM staging_online_retail),

    (SELECT COUNT(*)
     FROM cleaned_online_retail),

    (SELECT COUNT(*)
     FROM staging_online_retail)
    -
    (SELECT COUNT(*)
     FROM cleaned_online_retail);

SELECT *
FROM etl_audit_log
ORDER BY executed_at DESC;