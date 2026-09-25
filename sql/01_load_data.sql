-- 01_load_data.sql
-- Loads the four raw CSVs into SQLite and adds indexes for the join keys.
-- Run from the project root:  sqlite3 ecommerce.db < sql/01_load_data.sql

DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS products;

.mode csv
.import data/ecommerce_sales_customer_analytics_150k.csv orders
.import data/customer_master.csv customers
.import data/order_items.csv order_items
.import data/product_catalog.csv products
.mode list

CREATE INDEX ix_orders_id       ON orders(order_id);
CREATE INDEX ix_orders_customer ON orders(customer_id);
CREATE INDEX ix_items_order     ON order_items(order_id);
CREATE INDEX ix_items_product   ON order_items(product_id);
CREATE INDEX ix_products_id     ON products(product_id);
CREATE INDEX ix_customers_id    ON customers(customer_id);
