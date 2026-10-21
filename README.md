# Qafila gross margin

Submitted by: <Deemah Alsalamah> — academy: @SDAIAAcademy

The task, rules and grading are in [BRIEF.md](BRIEF.md).

```bash
uv sync
uv run python tools/make_data.py          # data/
uv run python run.py                      # data/ -> warehouse/ (DuckDB + Iceberg)
uv run python tools/check.py              # contract self-check
```

> Replace every `<...>` below. Keep it short: tables and a few sentences are enough.

## Design

< Pipeline: SQLite + supplier CSV files → DuckDB raw → dbt staging → silver SCD2 + quality quarantine → gold weekly margin → Apache Iceberg. >


| Model | Layer | Grain (one row per ...) | Materialization |
|---|---|---|---|
| `stg_orders`, `stg_order_items`, `stg_products`, `stg_stores`, `stg_supplier_prices` | staging | Source record | View |
| `product_cost_history` | silver | SKU and price change date | Table |
| `weekly_margin` | gold | ISO week, city, and category | Table |
| `price_quarantine` | quality | Invalid supplier price record | Table |


**How the SCD2 history is built:** Supplier prices are sorted by SKU and date. If a price is missing for a week, the previous price is used, and unchanged prices do not create new records. If a correction file has a different price for the same SKU and date, the latest filename is used.

**How each order line finds its cost:** Delivered order lines are matched with the product cost based on the order date in Riyadh time. If no matching cost is found, the line and its revenue are still counted, but no cost is added.

## Data problems I found

## Data problems I found

| Problem | Where | Rows affected | What I did |
|---|---|---|---|
| Different cost formats, including commas and Arabic numbers | Supplier CSV files | Not counted separately | Converted the values to numbers before using them |
| Invalid costs and unknown SKUs | Supplier CSV files | 7 quarantined rows in total | Moved invalid records to `price_quarantine` |
| Different column names (`unit_cost` and `cost_sar`) | Supplier CSV files | Not counted separately | Combined both columns during ingestion |
| Duplicate prices for the same SKU and date | Supplier CSV files | Not counted separately | Used the price from the latest filename |
| Late price correction | W39 correction file | Not counted separately | Updated the price history while keeping older Iceberg snapshots |

## Tests

## Tests

| Test | On | What it protects against |
|---|---|---|
| `not_null` checks | Silver and gold models | Missing values in important columns |
| `test_weekly_margin_calculation` | `weekly_margin` | Incorrect margin calculation |
| `test_product_cost_history_duplicates` | `product_cost_history` | Duplicate prices for the same SKU and date |
| `test_product_cost_history_current` | `product_cost_history` | More or less than one current price per SKU |

All 11 dbt tests passed with no errors.

## Re-runs and the correction

## Re-runs and the correction

Running the pipeline again with the same data did not create any new changes in the three Iceberg tables.

The correction file was also tested by running the pipeline without it and then adding it back. The silver and gold tables were updated, while the older Iceberg snapshots were kept.

For example, SKU `QF-BAK-1058` had a cost of **3.58 SAR** on `2026-09-21` before the correction, and **3.45 SAR** after it.

| Version | Iceberg snapshot ID | Cost |
|---|---|---|
| Before correction | `8500223882310764741` | 3.58 SAR |
| After correction | `3644950258568609948` | 3.45 SAR |

Both versions were checked using Iceberg snapshots.


## What I'd do next

## What I'd do next

With much larger data, rebuilding all tables every time would become slow. The next improvement would be to process only new or changed records instead of reading everything again. Daily supplier files would also need better checks for duplicates and missing prices.

## AI assistance

AI was used to help understand the project requirements and explain dbt and Iceberg concepts more clearly and quickly. It also helped with writing and reviewing parts of the SQL and Python code, finding solutions to errors faster, and improving the wording and formatting of the README, including organizing the tables. AI also provided step-by-step guidance on using Git, connecting the local project to GitHub and uploading the project.