-- Business Rules Explanation for 'Adjustment'-- 
USE online_retail_analytics;

-- 1. How many invoices are there that have negative quantity, but are not cancellations? --
SELECT COUNT(*) AS negative_non_cancelled
FROM cleaned_online_retail
WHERE quantity < 0
  AND invoice_no NOT LIKE 'C%';
-- There are 1336 rows, so I need to specifically investigate these rows. -- 
    
-- 2. What are the patterns I observed in these negative_non_cancelled values?
SELECT
    invoice_no,
    stock_code,
    product_description,
    quantity,
    unit_price,
    customer_id,
    country
FROM cleaned_online_retail
WHERE quantity < 0
  AND invoice_no NOT LIKE 'C%'
ORDER BY invoice_no
LIMIT 100;

SELECT
    product_description,
    COUNT(*) AS row_count
FROM cleaned_online_retail
WHERE quantity < 0
  AND invoice_no NOT LIKE 'C%'
GROUP BY product_description
ORDER BY row_count DESC
LIMIT 50;
-- There are 862 nullable rows, the rest are: check, damaged, damages, ?, thrown away, etc. So labelling them as 'Adjustment' is reasonable. -- 

-- 3. I need to ensure that these adjustment invoices does not have any associated customer ids --
SELECT
    CASE
        WHEN customer_id IS NULL THEN 'Missing Customer'
        ELSE 'Identified Customer'
    END AS customer_status,
    COUNT(*) AS row_count
FROM cleaned_online_retail
WHERE quantity < 0
  AND invoice_no NOT LIKE 'C%'
GROUP BY customer_status;

/*
Negative quantities without a cancellation invoice prefix were classified as adjustments. 
Investigation showed that these records were primarily associated with missing descriptions 
or operational descriptions such as damaged stock, destroyed items, stock checks, and incorrect 
stock entries, suggesting inventory adjustments rather than customer cancellations.
*/ 