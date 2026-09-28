# Power BI Build Guide

This guide builds a 4-page dashboard from the tables in `dashboard_data/`. Each step ends with a ✅ **checkpoint**, a number you should see if everything is right. If it doesn't match, stop and fix that step before moving on.

**Time needed:** about 4–6 hours spread over a few sessions.

---

## Step 0: Set up Windows and Power BI (Mac only)

Power BI Desktop only runs on Windows. Your Mac has UTM installed, which can run Windows as a virtual machine.

1. **Get Windows 11 for ARM** from Microsoft's official download page (search "Download Windows 11 Arm64 ISO"). Windows runs without activation for personal use; it just shows a watermark.
2. In **UTM**: click **+** → **Virtualize** → **Windows** → select the ISO. Give it **8 GB RAM, 4 CPU cores and 80 GB of disk**. Tick **"Install drivers and SPICE tools"**.
3. Install Windows. Once it's running, install **Power BI Desktop** from the **Microsoft Store** (free).
4. **Move the data into Windows:** upload `powerbi/dashboard_data.zip` (13 MB) to your Google Drive, download it inside Windows, then right-click → **Extract All** into `C:\PowerBI\dashboard_data\`. Also copy `retail_theme.json` across the same way.

> If any of this gets stuck, tell me the exact error message and I'll help.

---

## Step 1: Load the data

1. Open Power BI Desktop → **Get data** → **Text/CSV**.
2. Load these four files one by one, clicking **Transform Data** (not Load) each time:
   - `fact_orders.csv`
   - `fact_order_items.csv`
   - `dim_customers.csv`
   - `revenue_waterfall.csv`
3. In **Power Query**, check the data types. Click the icon at the left of each column header to change it:

| Table | Column | Type |
|---|---|---|
| fact_orders | `order_date` | **Date** |
| fact_orders | `net_sales`, `profit`, `gross_sales`, `discount_amount` | **Fixed decimal (currency)** |
| fact_orders | `discount_pct`, `customer_rating` | **Decimal number** |
| fact_orders | `is_collected`, `is_unpaid_completed`, `quantity` | **Whole number** |
| dim_customers | `first_order`, `last_order` | **Date** |
| dim_customers | `revenue`, `profit`, `annual_revenue`, `cac` | **Fixed decimal** |
| dim_customers | `first_order_year`, `recency_days`, `completed_orders`, `r_score`, `f_score`, `m_score` | **Whole number** |
| fact_order_items | `net_sales`, `profit` | **Fixed decimal** |

4. Click **Close & Apply**.

✅ **Checkpoint:** go to **Table view** (grid icon on the left) and check the row counts at the bottom: fact_orders **138,116**, fact_order_items **397,569**, dim_customers **25,000**, revenue_waterfall **5**.

---

## Step 2: Create the date table

**Modeling** → **New table** → paste:

```DAX
dim_date =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2021, 1, 1 ), DATE ( 2025, 12, 31 ) ),
    "Year", YEAR ( [Date] ),
    "Quarter", "Q" & QUARTER ( [Date] ),
    "Month Num", MONTH ( [Date] ),
    "Month", FORMAT ( [Date], "mmm" ),
    "Year-Month", FORMAT ( [Date], "yyyy-mm" )
)
```

Then:
- Right-click `dim_date` → **Mark as date table** → choose `Date`.
- Select the `Month` column → **Column tools** → **Sort by column** → `Month Num`.
- Select `revenue_waterfall[stage]` → **Sort by column** → `sort_order`.

---

## Step 3: Build the data model (relationships)

Go to **Model view** (the third icon on the left). Drag between fields to create these relationships:

| From (one side) | To (many side) | Direction |
|---|---|---|
| `dim_customers[customer_id]` | `fact_orders[customer_id]` | Single |
| `dim_date[Date]` | `fact_orders[order_date]` | Single |
| `fact_orders[order_id]` | `fact_order_items[order_id]` | Single |

Leave `revenue_waterfall` **unconnected**. It only provides the stage names for the waterfall chart.

Your model should look like this (a "star schema", worth mentioning in interviews):

```
 dim_date ──┐
            ├──< fact_orders ──< fact_order_items
dim_customers┘
```

---

## Step 4: Create the measures

Measures are reusable calculations. Keeping them in one place is good practice:

1. **Home** → **Enter data** → name the table `_Measures` → **Load**.
2. Select `_Measures`, then **Modeling** → **New measure** for each block below.
3. Once you've added one measure, delete the default `Column1`.

### Revenue & cash
```DAX
Booked Revenue = SUM ( fact_orders[net_sales] )

Completed Revenue =
CALCULATE ( [Booked Revenue], fact_orders[order_status] = "Completed" )

Collected Revenue =
CALCULATE ( [Booked Revenue], fact_orders[is_collected] = 1 )

Collection Rate % = DIVIDE ( [Collected Revenue], [Booked Revenue] )

Unpaid Completed Revenue =
CALCULATE ( [Booked Revenue], fact_orders[is_unpaid_completed] = 1 )

Returned Revenue =
CALCULATE ( [Booked Revenue], fact_orders[order_status] = "Returned" )

Cancelled Revenue =
CALCULATE ( [Booked Revenue], fact_orders[order_status] = "Cancelled" )

Pending Revenue =
CALCULATE ( [Booked Revenue], fact_orders[order_status] = "Pending" )

Paid but Pending Orders =
CALCULATE (
    COUNTROWS ( fact_orders ),
    fact_orders[order_status] = "Pending",
    fact_orders[payment_status] = "Paid"
)
```

### Waterfall (responds to slicers, unlike a fixed table)
```DAX
Waterfall Amount =
SWITCH (
    SELECTEDVALUE ( revenue_waterfall[stage] ),
    "Booked revenue", [Booked Revenue],
    "Returned", - [Returned Revenue],
    "Cancelled", - [Cancelled Revenue],
    "Stuck in Pending", - [Pending Revenue],
    "Completed but unpaid", - [Unpaid Completed Revenue]
)
```

### Profitability
```DAX
Completed Profit =
CALCULATE ( SUM ( fact_orders[profit] ), fact_orders[order_status] = "Completed" )

Profit Margin % = DIVIDE ( [Completed Profit], [Completed Revenue] )

Loss-Making Orders =
CALCULATE (
    COUNTROWS ( fact_orders ),
    fact_orders[order_status] = "Completed",
    fact_orders[profit] < 0
)

Discount Cap Uplift =
-- Extra profit if discounts were capped at 30%, assuming 20% of those orders are lost
VAR AffectedOrders =
    FILTER (
        fact_orders,
        fact_orders[order_status] = "Completed"
            && fact_orders[discount_amount] > 0.30 * fact_orders[gross_sales]
    )
VAR ProfitToday = SUMX ( AffectedOrders, fact_orders[profit] )
VAR ProfitCapped =
    0.8 * SUMX (
        AffectedOrders,
        fact_orders[profit] + fact_orders[discount_amount] - 0.30 * fact_orders[gross_sales]
    )
RETURN ProfitCapped - ProfitToday

Item Revenue =
CALCULATE ( SUM ( fact_order_items[net_sales] ), fact_orders[order_status] = "Completed" )

Item Margin % =
DIVIDE (
    CALCULATE ( SUM ( fact_order_items[profit] ), fact_orders[order_status] = "Completed" ),
    [Item Revenue]
)
```

### Orders & operations
```DAX
Orders = COUNTROWS ( fact_orders )

Return Rate % =
DIVIDE ( CALCULATE ( [Orders], fact_orders[order_status] = "Returned" ), [Orders] )

Cancel Rate % =
DIVIDE ( CALCULATE ( [Orders], fact_orders[order_status] = "Cancelled" ), [Orders] )

Delayed % =
DIVIDE (
    CALCULATE ( [Orders], fact_orders[delivery_status] = "Delayed" ),
    CALCULATE ( [Orders], fact_orders[order_status] = "Completed" )
)

Avg Rating = AVERAGE ( fact_orders[customer_rating] )
```

### Customers
```DAX
Customers = COUNTROWS ( dim_customers )

Lapsed Customers =
CALCULATE ( [Customers], dim_customers[recency_days] > 365 )

Annual Revenue at Risk =
CALCULATE (
    SUM ( dim_customers[annual_revenue] ),
    dim_customers[rfm_segment] IN { "Cannot Lose Them", "At Risk" }
)

Segment Bar Color =
-- Highlights the two win-back segments in orange; everything else blue
IF (
    SELECTEDVALUE ( dim_customers[rfm_segment] ) IN { "Cannot Lose Them", "At Risk" },
    "#eb6834",
    "#2a78d6"
)

Discount Bar Color =
IF ( SELECTEDVALUE ( fact_orders[discount_band] ) = "5. 35%+", "#d03b3b", "#2a78d6" )
```

**Formatting:** select each measure and set its format in **Measure tools**:
- Revenue and profit measures → **Currency**, 1 decimal place. Set display units to **Millions** on the visuals themselves.
- `%` measures → **Percentage**, 1 decimal place.
- `Avg Rating` → Decimal, 2 places.

✅ **Checkpoint:** drop each measure onto a blank **Card** visual (no filters applied) and compare with this table:

| Measure | Should show |
|---|---|
| Booked Revenue | $177.1M |
| Completed Revenue | $144.2M |
| Collected Revenue | $129.9M |
| Collection Rate % | 73.3% |
| Unpaid Completed Revenue | $14.3M |
| Completed Profit | $59.8M |
| Profit Margin % | 41.4% |
| Loss-Making Orders | 1,229 |
| Discount Cap Uplift | $1.4M |
| Return Rate % | 6.9% |
| Cancel Rate % | 6.1% |
| Delayed % | 14.9% |
| Avg Rating | 3.68 |
| Paid but Pending Orders | 1,997 |
| Lapsed Customers | 9,819 |
| Annual Revenue at Risk | $12.2M |

If they all match, your model is correct. That's the hard part done.

---

## Step 5: Apply the theme and set up the canvas

1. **View** → **Themes** → **Browse for themes** → select `retail_theme.json`.
2. **Format page** (paintbrush with the canvas selected) → **Canvas settings**: 16:9. **Canvas background**: color `#F9F9F7`, transparency 0%.
3. For every visual, go to **Format** → **General** → **Effects**. Turn **Background** on (white), **Visual border** on (color `#E1E0D9`, rounded corners 8px).

**Design rules for the whole dashboard:**
- **Write titles that state the finding, not the chart's contents.** "27% of booked revenue never becomes cash" beats "Revenue by status". This is the single thing that makes a dashboard look senior.
- Use one color (blue `#2a78d6`) by default. Only highlight what matters: orange `#eb6834` for "focus here", red `#d03b3b` for "this is a problem".
- Turn off gridlines on bar and column charts, and turn on data labels instead.
- Don't use pie charts, 3D charts, or two y-axes on one chart.

---

## Step 6: Build the pages

### Page 1: Executive Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│ Revenue & Retention Review, 2021–2025     [Year ▾] [Country ▾] [Channel ▾] │
├────────────┬────────────┬────────────┬────────────┬────────────┤
│  Booked    │ Collected  │ Collection │  Profit    │  Lapsed    │
│  $177.1M   │  $129.9M   │  rate 73%  │ margin 41% │  9,819     │
├────────────┴────────────┴──────┬─────┴────────────┴────────────┤
│  WATERFALL                     │  LINE: Completed revenue       │
│  27% of booked revenue never   │  by month — "Revenue has been  │
│  becomes cash                  │  flat for five years"          │
│                                ├────────────────────────────────┤
│                                │  COLUMN: New customers by year │
│                                │  "New customers down 97%"      │
└────────────────────────────────┴────────────────────────────────┘
```

| Visual | Fields | Settings |
|---|---|---|
| **Text box** (title) | — | "Revenue & Retention Review, 2021–2025", 18pt Segoe UI Semibold |
| **Slicers** ×3 | `dim_date[Year]`, `dim_customers[customer_country]`, `fact_orders[sales_channel]` | Style: **Dropdown** |
| **Cards** ×5 | Booked Revenue, Collected Revenue, Collection Rate %, Profit Margin %, Lapsed Customers | Display units: Millions for $; add a category label |
| **Waterfall** | Category: `revenue_waterfall[stage]` · Y-axis: `Waterfall Amount` | Sentiment colors: Increase `#2a78d6`, Decrease `#d03b3b`, Total `#0ca30c`. Data labels on, in Millions. Sort by stage ascending. Title: **"27% of booked revenue never becomes cash"** |
| **Line chart** | X: `dim_date[Year-Month]` · Y: `Completed Revenue` | Line width 2px, no markers. Title: **"Completed revenue has been flat for five years"** |
| **Column chart** | X: `dim_customers[first_order_year]` · Y: `Customers` | X-axis type: **Categorical**. Filter: `first_order_year` is not blank. Data labels on. Title: **"New customer acquisition fell 97% since 2021"** |

Then **sync the slicers** across all pages: **View** → **Sync slicers** → tick every page.

> The "New customers by year" chart doesn't respond to the Year slicer. That's intended, because it's based on each customer's first order date.

### Page 2: Revenue Leakage & Operations

| Visual | Fields | Settings / Title |
|---|---|---|
| **Matrix** | Rows: `order_status` · Columns: `payment_status` · Values: `Booked Revenue` | Cell elements → Background color → gradient white → `#2a78d6`. Title: **"Where booked revenue ends up"** |
| **Column chart** | X: `dim_date[Year]` · Y: `Unpaid Completed Revenue` | Color `#d03b3b`. Title: **"~$2.8M of 'completed' orders go unpaid every year, even from 2021"** |
| **Card** | `Paid but Pending Orders` | Label: "Customers who paid but are still waiting" |
| **Bar chart** | Y: `return_reason` · X: `Returned Revenue` | Filter: return_reason is not blank. Title: **"No single return reason dominates; fix processes, not one product"** |
| **Column chart** | X: `shipping_method` · Y: `Delayed %` | Title: **"Express is delayed as often as Economy (15%)"** |
| **Column chart** | X: `delivery_status` · Y: `Avg Rating` | Y-axis start at 0. Title: **"Late orders are rated 3.2★ vs 3.7★ on time"** |

### Page 3: Profitability & Discounts

| Visual | Fields | Settings / Title |
|---|---|---|
| **Column chart** | X: `discount_band` · Y: `Profit Margin %` | Columns → Color → **fx** → Format style: *Field value* → `Discount Bar Color`. Title: **"Discounts above 35% cut margin to 18%"** |
| **Column chart** | X: `discount_band` · Y: `Loss-Making Orders` | Same **fx** color. Title: **"Every loss-making order had a 35%+ discount"** |
| **Card** | `Discount Cap Uplift` | Label: "Extra profit from a 30% discount cap (assumes 20% of orders lost)" |
| **Scatter chart** | Values: `product_category` · X: `Item Revenue` · Y: `Item Margin %` | Category labels on. Title: **"Electronics: biggest category, thinnest margin (33%)"** |
| **Table** | `product_category`, `Item Revenue`, `Item Margin %` | Sorted by revenue. Conditional font color on margin |

### Page 4: Customers & Retention

| Visual | Fields | Settings / Title |
|---|---|---|
| **Cards** ×3 | `Customers`, `Lapsed Customers`, `Annual Revenue at Risk` | — |
| **Bar chart** | Y: `rfm_segment` · X: Sum of `annual_revenue` | Filter out "No Completed Orders". Bars → **fx** → Field value → `Segment Bar Color`. Title: **"4,237 lapsed high-value customers = $12.2M a year at risk"** |
| **Bar chart** | Y: `rfm_segment` · X: `Customers` | Same colors. Title: "Customers per segment" |
| **Table** (win-back list) | `customer_id`, `customer_country`, `rfm_segment`, `completed_orders`, `revenue`, `recency_days` | Filter: rfm_segment is "Cannot Lose Them" or "At Risk". Sort by revenue descending. Title: **"Win-back target list: highest-value lapsed customers first"** |

The win-back table is what a CRM manager would actually use. Point it out in interviews.

---

## Step 7: Finishing touches

1. **Navigation:** on each page, **Insert** → **Buttons** → **Navigator** → **Page navigator** at the top.
2. **Tooltips:** on the waterfall, add `Orders` to the tooltip field so hovering shows order counts.
3. **Alt text:** on each visual, go to **Format** → **General** → **Alt text** and write one sentence (for accessibility, which reviewers do notice).
4. **Check every page with the Year slicer set to 2025.** No visual should break or show "Blank".
5. **Save** as `Retail_Revenue_Retention.pbix` in the `powerbi/` folder.

---

## Step 8: Share it (without a work email)

Power BI's "Publish to web" needs a work or school account, so for a Gmail account:

1. **Screenshots:** one clean full-page screenshot per page. Save them as `powerbi/screenshots/1_overview.png` and so on, and show them in the README.
2. **PDF:** **File** → **Export** → **Export to PDF**. Recruiters can open it without Power BI.
3. **The .pbix file** goes on GitHub so technical reviewers can open it.
4. **Optional:** a 60-second screen recording clicking through the slicers. Upload it to YouTube (unlisted) or LinkedIn and link it from the README.

---

## Interview talking points

- **"Why a star schema?"** It makes filters flow in one direction (from dimensions to facts) and keeps measures fast and predictable.
- **"Why is the waterfall built from a measure instead of the fixed table?"** So it responds to the Year, Country and Channel slicers.
- **"Why not show $177M revenue?"** Because $32.9M of it was never a completed sale. I defined revenue as completed orders and showed collected cash separately.
- **"What would you add with more data?"** Marketing spend (for ROI by channel), website sessions (for conversion rates), and customer sign-up dates (to confirm the acquisition decline).
