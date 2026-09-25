-- 06_dashboard_exports.sql
-- Writes a clean star schema for Power BI / Tableau into dashboard_data/.
-- Requires 05_customer_retention_rfm.sql to have run first (uses the rfm table).
--
--   dim_customers (1) ──< fact_orders (1) ──< fact_order_items >── (product columns included)
--   dim_date is created inside Power BI with DAX (see POWERBI_GUIDE.md).
.headers on
.mode csv

-- One row per order. Customer attributes live in dim_customers, not here.
.output dashboard_data/fact_orders.csv
SELECT order_id, order_date, order_status, payment_status, delivery_status,
       sales_channel, marketing_channel, payment_method, shipping_method, warehouse,
       customer_id,
       quantity + 0 AS quantity, gross_sales + 0 AS gross_sales,
       discount_amount + 0 AS discount_amount,
       round(discount_amount / gross_sales, 4) AS discount_pct,
       CASE
         WHEN discount_amount / gross_sales < 0.05 THEN '1. 0-5%'
         WHEN discount_amount / gross_sales < 0.15 THEN '2. 5-15%'
         WHEN discount_amount / gross_sales < 0.25 THEN '3. 15-25%'
         WHEN discount_amount / gross_sales < 0.35 THEN '4. 25-35%'
         ELSE '5. 35%+' END AS discount_band,
       net_sales + 0 AS net_sales, profit + 0 AS profit,
       NULLIF(customer_rating, '') AS customer_rating,
       NULLIF(return_reason, '') AS return_reason,
       CASE WHEN order_status = 'Completed' AND payment_status = 'Paid' THEN 1 ELSE 0 END AS is_collected,
       CASE WHEN order_status = 'Completed' AND payment_status = 'Pending' THEN 1 ELSE 0 END AS is_unpaid_completed
FROM orders;

-- One row per customer (all 25,000), with RFM results where they have completed orders.
.output dashboard_data/dim_customers.csv
SELECT c.customer_id, c.customer_segment, c.customer_country, c.region,
       c.customer_age + 0 AS customer_age, c.gender,
       c.customer_acquisition_cost + 0 AS cac,
       r.first_order, CAST(strftime('%Y', r.first_order) AS INTEGER) AS first_order_year,
       r.last_order, r.orders AS completed_orders, r.revenue, r.profit,
       CAST(r.recency_days AS INTEGER) AS recency_days,
       r.r AS r_score, r.f AS f_score, r.m AS m_score,
       COALESCE(r.segment, 'No Completed Orders') AS rfm_segment,
       round(r.annual_revenue, 2) AS annual_revenue
FROM customers c LEFT JOIN rfm r USING (customer_id);

-- One row per product in an order, with product attributes included.
.output dashboard_data/fact_order_items.csv
SELECT i.order_id, i.product_id, p.product_category, p.product_subcategory, p.brand,
       i.quantity + 0 AS quantity, i.net_sales + 0 AS net_sales, i.profit + 0 AS profit
FROM order_items i JOIN products p USING (product_id);

-- Booked revenue → collected revenue, for the waterfall chart.
.output dashboard_data/revenue_waterfall.csv
SELECT 1 AS sort_order, 'Booked revenue' AS stage, round(sum(net_sales), 2) AS amount FROM orders
UNION ALL SELECT 2, 'Returned', -round(sum(net_sales), 2) FROM orders WHERE order_status = 'Returned'
UNION ALL SELECT 3, 'Cancelled', -round(sum(net_sales), 2) FROM orders WHERE order_status = 'Cancelled'
UNION ALL SELECT 4, 'Stuck in Pending', -round(sum(net_sales), 2) FROM orders WHERE order_status = 'Pending'
UNION ALL SELECT 5, 'Completed but unpaid', -round(sum(net_sales), 2) FROM orders
          WHERE order_status = 'Completed' AND payment_status = 'Pending';
.output stdout
