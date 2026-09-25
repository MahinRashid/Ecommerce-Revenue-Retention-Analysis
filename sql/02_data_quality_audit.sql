-- 02_data_quality_audit.sql
-- Answers: can we trust this data, and what is missing?
.headers on
.mode column

-- Row counts and date range
SELECT count(*) AS orders, count(DISTINCT order_id) AS unique_orders,
       count(DISTINCT customer_id) AS customers,
       min(order_date) AS first_date, max(order_date) AS last_date
FROM orders;

-- Referential integrity: every key should join (all expected to be 0)
SELECT
  (SELECT count(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)) AS orders_missing_customer,
  (SELECT count(*) FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.order_id = i.order_id))     AS items_missing_order,
  (SELECT count(*) FROM order_items i WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.product_id = i.product_id)) AS items_missing_product,
  (SELECT count(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id))  AS customers_never_ordered;

-- ISSUE 1: headline revenue in dataset_statistics.csv counts every order status
SELECT round(sum(net_sales), 2) AS revenue_all_statuses,
       round(sum(CASE WHEN order_status = 'Completed' THEN net_sales END), 2) AS revenue_completed_only,
       round(sum(net_sales) - sum(CASE WHEN order_status = 'Completed' THEN net_sales END), 2) AS overstatement
FROM orders;

-- ISSUE 2: order header totals disagree with the sum of their line items
WITH item_totals AS (
  SELECT order_id, sum(quantity) AS qty, sum(net_sales) AS net
  FROM order_items GROUP BY order_id
)
SELECT count(*) AS orders_compared,
       sum(o.quantity <> t.qty) AS quantity_mismatch,
       sum(abs(o.net_sales - t.net) > 1) AS net_sales_mismatch
FROM orders o JOIN item_totals t USING (order_id);

-- ISSUE 3: contradictory status combinations
SELECT order_status, delivery_status, payment_status, count(*) AS n
FROM orders GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;

-- ISSUE 4: stored customer_order_count disagrees with actual order count
WITH a AS (
  SELECT customer_id, count(*) AS actual, max(customer_order_count + 0) AS stored
  FROM orders GROUP BY customer_id
)
SELECT count(*) AS customers, sum(actual <> stored) AS count_mismatch FROM a;

-- ISSUE 5: currency label does not change amounts (INR orders average the same as USD)
SELECT currency, count(*) AS n, round(avg(net_sales), 0) AS avg_net_sales
FROM orders GROUP BY currency;

-- ISSUE 6: ratings only exist for completed orders (no voice from returns/cancellations)
SELECT order_status, count(*) AS n, sum(customer_rating = '') AS missing_rating
FROM orders GROUP BY order_status;

-- ISSUE 7: coupon use has no effect on discount depth
SELECT coupon_code <> '' AS has_coupon, count(*) AS n,
       round(avg(discount_amount / gross_sales) * 100, 1) AS avg_discount_pct
FROM orders WHERE order_status = 'Completed' GROUP BY 1;
