-- 05_customer_retention_rfm.sql
-- Answers: who are our valuable customers, who is slipping away, and what is at risk?
-- Analysis date = 2025-12-31 (last date in the data). Only completed orders count.
.headers on
.mode column

DROP TABLE IF EXISTS cust_summary;
CREATE TABLE cust_summary AS
SELECT o.customer_id,
       min(o.order_date) AS first_order,
       max(o.order_date) AS last_order,
       count(*) AS orders,
       round(sum(o.net_sales), 2) AS revenue,
       round(sum(o.profit), 2) AS profit,
       julianday('2025-12-31') - julianday(max(o.order_date)) AS recency_days,
       c.customer_acquisition_cost + 0 AS cac,
       c.customer_segment, c.customer_country, c.region
FROM orders o JOIN customers c USING (customer_id)
WHERE o.order_status = 'Completed'
GROUP BY o.customer_id;

-- New customers acquired per year (first completed order)
SELECT strftime('%Y', first_order) AS year, count(*) AS new_customers
FROM cust_summary GROUP BY 1;

-- Average gap between repeat purchases (used to define "lapsed")
WITH gaps AS (
  SELECT julianday(order_date) - julianday(lag(order_date) OVER (PARTITION BY customer_id ORDER BY order_date)) AS gap
  FROM orders WHERE order_status = 'Completed'
)
SELECT round(avg(gap), 0) AS avg_days_between_orders FROM gaps;

-- RFM scoring: 1-5 for Recency, Frequency, Monetary; 5 = best
DROP TABLE IF EXISTS rfm;
CREATE TABLE rfm AS
WITH scored AS (
  SELECT *,
         ntile(5) OVER (ORDER BY recency_days DESC) AS r,
         ntile(5) OVER (ORDER BY orders)            AS f,
         ntile(5) OVER (ORDER BY revenue)           AS m
  FROM cust_summary
)
SELECT *,
       CASE
         WHEN r >= 4 AND f >= 4 THEN 'Champions'
         WHEN r >= 3 AND f >= 3 THEN 'Loyal'
         WHEN r >= 4 AND f <= 2 THEN 'New / Promising'
         WHEN r <= 2 AND f >= 4 THEN 'Cannot Lose Them'
         WHEN r <= 2 AND f = 3  THEN 'At Risk'
         WHEN r = 3  AND f <= 2 THEN 'Needs Attention'
         ELSE 'Hibernating / Lost'
       END AS segment,
       -- revenue per active year, a simple annual run-rate
       revenue / max(1.0, (julianday(last_order) - julianday(first_order)) / 365.0) AS annual_revenue
FROM scored;

SELECT segment, count(*) AS customers,
       round(avg(recency_days), 0) AS avg_days_since_order,
       round(avg(orders), 1) AS avg_orders,
       round(sum(revenue) / 1e6, 2) AS lifetime_revenue_m,
       round(sum(annual_revenue) / 1e6, 2) AS annual_revenue_m
FROM rfm GROUP BY segment ORDER BY lifetime_revenue_m DESC;

-- Revenue concentration: share of revenue from each customer decile
WITH d AS (SELECT revenue, ntile(10) OVER (ORDER BY revenue DESC) AS decile FROM cust_summary)
SELECT decile, round(100.0 * sum(revenue) / (SELECT sum(revenue) FROM cust_summary), 1) AS pct_of_revenue
FROM d GROUP BY decile;
