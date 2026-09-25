#!/bin/sh
# Rebuilds the database and reruns every analysis step. Outputs go to outputs/.
set -e
cd "$(dirname "$0")"
rm -f ecommerce.db
sqlite3 ecommerce.db < sql/01_load_data.sql
for f in 02_data_quality_audit 03_revenue_leakage 04_discounts_and_margin 05_customer_retention_rfm; do
  echo "Running $f..."
  sqlite3 ecommerce.db < "sql/$f.sql" > "outputs/$f.txt"
done
sqlite3 ecommerce.db < sql/06_dashboard_exports.sql
echo "Done. Results in outputs/, dashboard tables in dashboard_data/."
