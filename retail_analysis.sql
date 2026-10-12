-- =====================================================================
-- Retail Sales Analysis 2022-2025  |  PostgreSQL
-- Data: data/sales_cleaned.csv (output of python/01_clean_data.py)
-- "Valid sale" = Valid_Sale = 'Yes'  (Completed, Shipped, Processing)
-- =====================================================================

-- ---------- 0. Create table and load data ----------
CREATE TABLE sales (
    transaction_id       VARCHAR(20) PRIMARY KEY,
    order_id             VARCHAR(20),
    customer_id          VARCHAR(20),
    customer_name        VARCHAR(100),
    customer_age         NUMERIC,
    customer_gender      VARCHAR(20),
    customer_segment     VARCHAR(30),
    order_date           DATE,
    order_time           TIME,
    sales_channel        VARCHAR(30),
    store_id             VARCHAR(20),
    store_name           VARCHAR(60),
    country              VARCHAR(40),
    region               VARCHAR(40),
    city                 VARCHAR(40),
    product_id           VARCHAR(10),
    product_name         VARCHAR(60),
    product_category     VARCHAR(40),
    product_subcategory  VARCHAR(40),
    quantity             INT,
    unit_price           NUMERIC(12,2),
    discount_percentage  NUMERIC(5,1),
    sales_amount         NUMERIC(12,2),
    cost_amount          NUMERIC(12,2),
    profit               NUMERIC(12,2),
    payment_method       VARCHAR(30),
    order_status         VARCHAR(20),
    shipping_method      VARCHAR(20),
    delivery_days        NUMERIC,
    return_flag          VARCHAR(3),
    return_reason        VARCHAR(30),
    sales_representative VARCHAR(60),
    promotion_code       VARCHAR(30),
    customer_rating      NUMERIC,
    inventory_level      NUMERIC,
    order_year           INT,
    data_issue           VARCHAR(100),
    valid_sale           VARCHAR(3),
    discount_band        VARCHAR(20),
    discount_band_order  INT
);
-- In psql:  \copy sales FROM 'data/sales_cleaned.csv' WITH (FORMAT csv, HEADER true)
-- (or use the pgAdmin Import/Export wizard with Header = on)

-- Small lookup tables so I can practise JOINs
CREATE TABLE products AS
SELECT DISTINCT product_id, product_name, product_category, product_subcategory FROM sales;

CREATE TABLE stores AS
SELECT DISTINCT store_id, store_name, city, country FROM sales;

-- ---------- 1. Sanity checks ----------
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT transaction_id) AS unique_transactions FROM sales;

SELECT valid_sale, COUNT(*) AS transactions, ROUND(SUM(sales_amount),0) AS revenue
FROM sales GROUP BY valid_sale;

-- ---------- 2. Headline KPIs ----------
SELECT ROUND(SUM(sales_amount),0)                           AS revenue,
       ROUND(SUM(profit),0)                                 AS profit,
       ROUND(100.0*SUM(profit)/SUM(sales_amount),1)         AS margin_pct,
       COUNT(*)                                             AS transactions,
       ROUND(AVG(sales_amount),0)                           AS avg_order_value
FROM sales WHERE valid_sale = 'Yes';

-- ---------- 3. Monthly revenue and profit ----------
SELECT DATE_TRUNC('month', order_date)::DATE AS month,
       ROUND(SUM(sales_amount),0) AS revenue,
       ROUND(SUM(profit),0)       AS profit
FROM sales WHERE valid_sale = 'Yes'
GROUP BY 1 ORDER BY 1;

-- ---------- 4. Year-over-year growth (window function) ----------
WITH yearly AS (
    SELECT order_year, SUM(sales_amount) AS revenue, SUM(profit) AS profit
    FROM sales WHERE valid_sale = 'Yes' GROUP BY order_year
)
SELECT order_year,
       ROUND(revenue,0) AS revenue,
       ROUND(100.0*(revenue - LAG(revenue) OVER (ORDER BY order_year))
             / LAG(revenue) OVER (ORDER BY order_year),1) AS revenue_growth_pct,
       ROUND(100.0*profit/revenue,1) AS margin_pct
FROM yearly ORDER BY order_year;

-- ---------- 5. Share of revenue earned in Q4 ----------
SELECT ROUND(100.0*SUM(CASE WHEN EXTRACT(MONTH FROM order_date) IN (10,11,12)
                            THEN sales_amount ELSE 0 END) / SUM(sales_amount),1) AS q4_share_pct
FROM sales WHERE valid_sale = 'Yes';

-- ---------- 6. Margin by category and subcategory (JOIN) ----------
SELECT p.product_category, p.product_subcategory,
       ROUND(SUM(s.sales_amount),0) AS revenue,
       ROUND(100.0*SUM(s.profit)/SUM(s.sales_amount),1) AS margin_pct
FROM sales s
JOIN products p ON s.product_id = p.product_id
WHERE s.valid_sale = 'Yes'
GROUP BY p.product_category, p.product_subcategory
HAVING SUM(s.sales_amount) > 50000
ORDER BY margin_pct;

-- ---------- 7. Discount band vs profit (my main finding) ----------
SELECT discount_band,
       COUNT(*)                                          AS transactions,
       SUM(CASE WHEN profit < 0 THEN 1 ELSE 0 END)       AS loss_orders,
       ROUND(SUM(sales_amount),0)                        AS revenue,
       ROUND(100.0*SUM(profit)/SUM(sales_amount),1)      AS margin_pct
FROM sales
WHERE valid_sale = 'Yes' AND discount_band <> 'Unknown'
GROUP BY discount_band, discount_band_order
ORDER BY discount_band_order;

-- ---------- 8. Do promo codes really control discounts? ----------
SELECT promotion_code,
       COUNT(*) AS transactions,
       ROUND(AVG(discount_percentage),1)             AS avg_discount_pct,
       ROUND(100.0*SUM(profit)/SUM(sales_amount),1)  AS margin_pct
FROM sales WHERE valid_sale = 'Yes'
GROUP BY promotion_code
ORDER BY avg_discount_pct DESC;

-- ---------- 9. Returns ----------
SELECT product_category,
       ROUND(100.0*SUM(CASE WHEN return_flag='Yes' THEN 1 ELSE 0 END)/COUNT(*),1) AS return_rate_pct
FROM sales GROUP BY product_category ORDER BY return_rate_pct DESC;

SELECT return_reason, COUNT(*) AS returned_orders
FROM sales WHERE return_flag = 'Yes'
GROUP BY return_reason ORDER BY returned_orders DESC;

-- ---------- 10. Top 10 products by revenue ----------
SELECT product_name,
       ROUND(SUM(sales_amount),0) AS revenue,
       ROUND(100.0*SUM(profit)/SUM(sales_amount),1) AS margin_pct
FROM sales WHERE valid_sale = 'Yes'
GROUP BY product_name ORDER BY revenue DESC LIMIT 10;

-- ---------- 11. Revenue and margin by country ----------
SELECT st.country,
       ROUND(SUM(s.sales_amount),0) AS revenue,
       ROUND(100.0*SUM(s.profit)/SUM(s.sales_amount),1) AS margin_pct
FROM sales s JOIN stores st ON s.store_id = st.store_id
WHERE s.valid_sale = 'Yes'
GROUP BY st.country ORDER BY revenue DESC;
