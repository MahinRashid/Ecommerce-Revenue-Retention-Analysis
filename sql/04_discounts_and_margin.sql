-- 04_discounts_and_margin.sql
-- Answers: are discounts buying profitable sales, or giving margin away?
.headers on
.mode column

-- Margin by discount depth (completed orders)
SELECT CASE
         WHEN discount_amount / gross_sales < 0.05 THEN '0-5%'
         WHEN discount_amount / gross_sales < 0.15 THEN '05-15%'
         WHEN discount_amount / gross_sales < 0.25 THEN '15-25%'
         WHEN discount_amount / gross_sales < 0.35 THEN '25-35%'
         ELSE '35%+' END AS discount_band,
       count(*) AS orders,
       round(100.0 * sum(profit) / sum(net_sales), 1) AS margin_pct,  -- total profit / total revenue
       sum(profit < 0) AS loss_making_orders,
       round(sum(profit) / 1e6, 2) AS profit_m
FROM orders WHERE order_status = 'Completed'
GROUP BY 1 ORDER BY 1;

-- Scenario: cap discounts at 30%, assuming 20% of those orders are lost
WITH affected AS (
  SELECT gross_sales AS g, discount_amount AS d, profit AS p
  FROM orders
  WHERE order_status = 'Completed' AND discount_amount / gross_sales > 0.30
)
SELECT count(*) AS orders_affected,
       round(avg(d / g) * 100, 1) AS current_avg_discount_pct,
       round(sum(p) / 1e6, 2) AS profit_today_m,
       round(0.8 * sum(p + (d - 0.30 * g)) / 1e6, 2) AS profit_with_cap_m,
       round((0.8 * sum(p + (d - 0.30 * g)) - sum(p)) / 1e6, 2) AS profit_uplift_m
FROM affected;

-- Category profitability (line-item level, completed orders)
SELECT p.product_category, round(sum(i.net_sales) / 1e6, 2) AS net_sales_m,
       round(100.0 * sum(i.profit) / sum(i.net_sales), 1) AS margin_pct,
       round(100.0 * sum(i.profit < 0) / count(*), 1) AS loss_line_pct
FROM order_items i
JOIN products p USING (product_id)
JOIN orders o USING (order_id)
WHERE o.order_status = 'Completed'
GROUP BY 1 ORDER BY net_sales_m DESC;

-- Delivery performance vs customer rating
SELECT delivery_status, count(*) AS orders,
       round(avg(customer_rating + 0), 2) AS avg_rating
FROM orders WHERE order_status = 'Completed' GROUP BY 1;
