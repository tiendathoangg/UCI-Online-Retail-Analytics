/*=========================================================
Project : Online Retail Sales Analytics
Layer   : Business Analytics / Sales Performance
Input   : fact_sales, dim_date, dim_country, dim_product, dim_customer
Output  : Sales performance KPIs, revenue trends, country performance, product rankings, cancellation rate, customer performance

Purpose 
- Evaluate overall business performance using completed revenue, net revenue, invoices, units sold, and identified customers.
- Analyze monthly revenue trends and month-over-month growth to identify periods of strong performance and significant declines.
- Compare sales performance across countries and products to identify key markets and top revenue-generating products.
- Assess cancellation rates and customer-level revenue to identify potential operational issues and high-value customers.

=========================================================*/
USE online_retail_analytics;
-- 1. Sales Performance -- 
-- What is the overall sales performace of the business? --
SELECT * 
FROM fact_sale;

SELECT
	ROUND(SUM(completed_revenue),2) AS total_completed_revernue,
    ROUND(SUM(net_revenue),2) AS total_net_revenue,
    COUNT(
		DISTINCT CASE
			WHEN is_completed = 1 THEN invoice_no
		END
	) AS completed_invoices,
    
    SUM(
		CASE
			WHEN is_completed = 1 THEN quantity
		END
	) AS units_sold,
    
    COUNT(
		DISTINCT CASE
			WHEN has_customer_id = 1 THEN customer_key
		END
	) AS identified_customers

FROM 
	fact_sales;
/*
- Total completed revenue: $10,642,110.80
- Total net revenue: $9,748,131.07
- Completed invoices: 19,960
- Units sold: 5,572,420
- Total identified customers: 4,372
*/

-- 2. Monthy Revenue Trend and Growth Rate --
-- How has net revenue changed over time? Which months generated the highest revenue? --
WITH monthly_sales AS (
	SELECT 
		d.calendar_year,
		d.calendar_month,
        d.month_name,
        SUM(f.net_revenue) AS total_net_revenue
	FROM fact_sales AS f
    JOIN dim_date AS d 
		ON f.date_key = d.date_key
	GROUP BY 
		d.calendar_year,
        d.calendar_month,
        d.month_name
),

sales_with_previous AS(
	SELECT *,
		LAG(total_net_revenue) OVER (
			ORDER BY calendar_year, calendar_month
	) AS previous_month_revenue
    FROM monthly_sales
)

SELECT
	calendar_year,
    calendar_month,
    month_name,
    
    ROUND(total_net_revenue, 2) AS total_net_revenue,
    ROUND(previous_month_revenue,2) AS previous_month_revenue,
    
    ROUND(
		(total_net_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0) * 100,
        2
	) AS growth_percentage
    
FROM sales_with_previous
ORDER BY
	calendar_year,
    calendar_month;
    
/* Note that the dataset starts with 1st December 2010 and ends with 9th December 2011,
therefore the previous_month_revenue of December 2010 is NULL */

/* May 2011 had the strongest groowth (46.66%), while there was a significant sales decline in December 2012 
(biggest contributor would be the only 9 dates covered in this month from the date range of this dataset)
*/

-- 3. Country Performance -- 
-- Which country generate the most revenue -- 
SELECT 
	co.country_name,
    ROUND(SUM(f.net_revenue),2) AS total_net_revenue,
    COUNT(DISTINCT f.invoice_no) AS total_invoices,
	COUNT(
		DISTINCT CASE
			WHEN f.has_customer_id = 1
            THEN f.customer_key
		END
	) AS identified_customers
FROM 
	fact_sales AS f
JOIN 
	dim_country AS co
    ON f.country_key = co.country_key
GROUP BY
	co.country_name
ORDER BY
	total_net_revenue DESC;

/* 
- The majority of sales is in the UK with the dominant number of customers.
- Investigations are needed in regions having a few amount of customers with 
a vast amount of invoices, such as EIRE, Hong Kong, etc. To identify where 
the purchases were made.
*/

-- 4. Top Products --
-- Which 10 products generate the highest completed revenue -- 
SELECT 
	f.product_key,	
    p.stock_code,
    p.product_description,
	ROUND(SUM(completed_revenue),2) AS completed_revenue,
    SUM(f.quantity) AS units_solde
FROM 
	fact_sales AS f
JOIN
	dim_product AS p
	ON f.product_key = p.product_key
WHERE
	f.is_completed = 1
GROUP BY 
	f.product_key
ORDER BY 
	completed_revenue DESC
LIMIT 10;
	
/*
DOT has the highest completed revenue while only having 706 units sold.
*/

-- 5. Cancellation Rate --
-- What percentage of invoices were cancelled? 14.81% --
SELECT
	COUNT(DISTINCT invoice_no) AS total_invoices,
    
    COUNT(
		DISTINCT CASE
			WHEN is_cancelled = 1
			THEN invoice_no
		END
	) AS cancelled_invoices,
    
    ROUND(
		COUNT(
			DISTINCT CASE
				WHEN is_cancelled = 1
                THEN invoice_no
			END
		)
        /
        COUNT(DISTINCT invoice_no)
        * 100,
        2
	) AS cancellation_rate
FROM 
	fact_sales;


-- 6. Customer/Order performance --
-- Who are the top 10 customers by net revenue? --

SELECT 
	c.customer_id,
	ROUND(SUM(net_revenue),2) AS net_revenue
FROM 
	fact_sales AS f
JOIN
	dim_customer AS c
	ON f.customer_key = c.customer_key
GROUP BY 
	c.customer_id
ORDER BY 
	net_revenue DESC
LIMIT 10;






