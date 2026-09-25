-- 03_revenue_leakage.sql
-- Answers: how much booked revenue never turns into collected cash?
.headers on
.mode column

-- Where the money goes, by order and payment status
SELECT order_status, payment_status, count(*) AS orders,
       round(sum(net_sales) / 1e6, 2) AS net_sales_m
FROM orders GROUP BY 1, 2 ORDER BY net_sales_m DESC;

-- Completed orders that were never paid, by year (aging receivables)
SELECT strftime('%Y', order_date) AS year, count(*) AS orders,
       round(sum(net_sales) / 1e6, 2) AS unpaid_m
FROM orders
WHERE order_status = 'Completed' AND payment_status = 'Pending'
GROUP BY 1;

-- Orders stuck in 'Pending' status, by year they were placed
SELECT strftime('%Y', order_date) AS year, count(*) AS stuck_orders,
       round(sum(net_sales) / 1e6, 2) AS net_sales_m
FROM orders WHERE order_status = 'Pending' GROUP BY 1;

-- Return reasons
SELECT return_reason, count(*) AS returns, round(sum(net_sales) / 1e6, 2) AS net_sales_m
FROM orders WHERE order_status = 'Returned' GROUP BY 1 ORDER BY returns DESC;
