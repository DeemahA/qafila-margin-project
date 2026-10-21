"""Qafila gross margin pipeline: raw files -> DuckDB -> dbt -> Iceberg.

    uv run python run.py --data-dir data --warehouse warehouse

Must work on an empty warehouse folder, and must be safe to run again on the same one.
The grader runs it on a dataset you haven't seen, so never hard-code file names, row counts or SKUs.
"""

from __future__ import annotations

import pyarrow as pa
from pyiceberg.exceptions import NoSuchTableError

import argparse
import os
import subprocess
import sys
from pathlib import Path

import duckdb
from pyiceberg.catalog.sql import SqlCatalog

DBT_DIR = Path(__file__).resolve().parent / "dbt"


def get_catalog(warehouse: Path) -> SqlCatalog:
    """The Iceberg catalog the grader reads. Don't change the name, the URI or the warehouse."""
    warehouse.mkdir(parents=True, exist_ok=True)
    return SqlCatalog("qafila", uri=f"sqlite:///{(warehouse / 'catalog.db').as_posix()}", warehouse=warehouse.resolve().as_posix())


def ingest(data_dir: Path, db: Path) -> None:
    """Step 1: land the sources in DuckDB, schema `raw`, exactly as they arrive.

    - From data_dir/qafila_oltp.sqlite: orders, order_items, products, stores.
    - Every data_dir/suppliers/prices_*.csv, keeping the file name of each row.

    Running this twice must not duplicate anything.
    """
    with duckdb.connect(str(db)) as con:  # closes the file before dbt opens it
        con.sql("CREATE SCHEMA IF NOT EXISTS raw")
        #raise NotImplementedError("Step 1: load the sources into the raw schema")
        sqlite_path = data_dir / "qafila_oltp.sqlite"

        con.execute("INSTALL sqlite")
        con.execute("LOAD sqlite")

       
        con.execute(
    f"ATTACH '{sqlite_path.resolve().as_posix().replace(chr(39), chr(39)*2)}' AS source_db (TYPE SQLITE, READ_ONLY)"
)

        for table in ["orders", "order_items", "products", "stores"]:
            con.execute(
                f"CREATE OR REPLACE TABLE raw.{table} AS "
                f"SELECT * FROM source_db.{table}"
            )

        con.execute("DETACH source_db")

        price_files = sorted((data_dir / "suppliers").glob("prices_*.csv"))

        if not price_files:
            raise FileNotFoundError("No supplier price files found")

        con.execute("""
            CREATE OR REPLACE TABLE raw.supplier_prices AS
            SELECT
                supplier_id,
                sku,
                product_name_ar,
                COALESCE(unit_cost, cost_sar) AS unit_cost,
                valid_from,
                min_order_qty,
                currency,
                filename
            FROM read_csv(
                ?,
                union_by_name = true,
                all_varchar = true,
                filename = true
            )
        """, [[str(file.resolve()) for file in price_files]])

def transform(db: Path) -> None:
    """Steps 2-4: build and test the dbt project in dbt/ against the DuckDB file.

    dbt runs in its own process: in this one it would keep the DuckDB file open and block publish().
    """
    env = {**os.environ, "QAFILA_DUCKDB": str(db.resolve())}
    cmd = [sys.executable, "-c", "from dbt.cli.main import cli; cli()",
           "build", "--project-dir", str(DBT_DIR), "--profiles-dir", str(DBT_DIR)]
    if subprocess.run(cmd, env=env).returncode != 0:
        raise SystemExit("dbt build failed")


def publish(db: Path, warehouse: Path) -> None:
    """Step 5: publish three dbt models to Iceberg (see the brief for the exact columns).

        silver.product_cost_history   gold.weekly_margin   quality.price_quarantine

    Update existing tables in place, never drop and recreate them: the table's snapshots are
    how we see what a number was before the supplier's correction arrived.
    """
    catalog = get_catalog(warehouse)

    # Create namespaces if they don't exist
    for namespace in ["silver", "gold", "quality"]:
        if not catalog.namespace_exists(namespace):
            catalog.create_namespace(namespace)

    # Tables to publish from DuckDB to Iceberg
    tables = [
        ("silver", "product_cost_history"),
        ("gold", "weekly_margin"),
        ("quality", "price_quarantine"),
    ]

     # Read the dbt tables from DuckDB
    with duckdb.connect(str(db), read_only=True) as con:
        for schema_name, table_name in tables:
            table_id = f"{schema_name}.{table_name}"

            # Convert the DuckDB result to an Arrow table
            arrow_table = con.execute(
                f"SELECT * FROM {table_id}"
            ).fetch_arrow_table()

            print(f"Ready to publish: {table_id} ({arrow_table.num_rows} rows)")

            # Create the Iceberg table only if it doesn't exist
            iceberg_table = catalog.create_table_if_not_exists(
                identifier=table_id,
                schema=arrow_table.schema
            )

            print(f"Iceberg table ready: {table_id}")

            # Read the existing data from Iceberg
            existing_data = iceberg_table.scan().to_arrow()

            # Compare rows without depending on their order
            sort_columns = arrow_table.column_names

            new_sorted = arrow_table.sort_by(
                [(col, "ascending") for col in sort_columns]
            )

            existing_sorted = existing_data.sort_by(
                [(col, "ascending") for col in sort_columns]
            )

            # Skip publishing if nothing changed
            if new_sorted.equals(existing_sorted):
                print(f"No changes: {table_id}")
                continue

            # Update the table and keep its previous snapshots
            iceberg_table.overwrite(arrow_table)

            print(f"Published: {table_id}")
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--data-dir", type=Path, default=Path("data"))
    ap.add_argument("--warehouse", type=Path, default=Path("warehouse"))
    args = ap.parse_args()

    args.warehouse.mkdir(parents=True, exist_ok=True)
    db = args.warehouse / "qafila.duckdb"
    ingest(args.data_dir, db)
    transform(db)
    publish(db, args.warehouse)
    print(f"done: {args.warehouse.resolve()}")


if __name__ == "__main__":
    main()
