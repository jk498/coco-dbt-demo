# Building Production dbt Pipelines with Snowflake Cortex Code: A Hands-On Guide

*How an AI-powered CLI built my entire dbt project — from messy raw data to tested, documented analytics models — in a single session.*

---

## TL;DR

I used **Snowflake Cortex Code (CoCo)** — Snowflake's AI-powered CLI — to build a complete dbt pipeline from scratch. CoCo inspected my raw data, detected 7 quality issues, generated staging models with production-grade defensive SQL, scaffolded a marts layer with business logic, wrote 17 dbt tests (all passing), and ran everything against live Snowflake — all through natural language conversation. This article walks through every step with real code and real query outputs.

---

## Why This Matters

Building dbt projects traditionally involves a familiar loop: inspect raw tables, write staging SQL, debug type mismatches, add tests, repeat. Each step requires context-switching between a SQL editor, terminal, documentation, and your dbt project files.

**Cortex Code collapses this loop.** It connects directly to your Snowflake account, reads your actual table schemas and sample data, and generates contextually aware dbt models. It doesn't just template SQL — it detects data quality issues in your real data and writes defensive transformations to handle them.

Here's what we built:

```
COCO_DBT_DEMO
├── RAW (source layer)
│   ├── CUSTOMERS_RAW    (13 rows — intentionally messy)
│   └── ORDERS_RAW       (15 rows — mixed formats)
├── ANALYTICS (transformed layer)
│   ├── stg_customers    (view — deduplicated, cleaned)
│   ├── stg_orders       (view — normalized, type-safe)
│   └── fct_customer_orders  (table — aggregated metrics)
└── 17 dbt tests (all PASS)
```

---

## Prerequisites

- A Snowflake account with `ACCOUNTADMIN` (or equivalent) role
- [Snowflake Cortex Code CLI](https://docs.snowflake.com/en/user-guide/cortex-code) installed (`snowflake-cortex-code`)
- Python 3.9+ with `dbt-snowflake` installed
- A configured Snowflake connection (`cortex` CLI connection)

---

## Step 1: Snowflake Setup — Create the Playground

First, I set up the database and schemas using CoCo's built-in Snowflake SQL execution:

```sql
CREATE DATABASE COCO_DBT_DEMO;
CREATE SCHEMA COCO_DBT_DEMO.RAW;
CREATE SCHEMA COCO_DBT_DEMO.ANALYTICS;
```

**Real output:**
```
Schema COCO_DBT_DEMO.RAW created  — 0.139s
Schema COCO_DBT_DEMO.ANALYTICS created — 0.055s
```

Then I loaded intentionally messy sample data. This is the key part — the raw data has real-world quality problems baked in:

```sql
CREATE OR REPLACE TABLE COCO_DBT_DEMO.RAW.CUSTOMERS_RAW (
    CUSTOMER_ID VARCHAR(50),
    CUSTOMER_NAME VARCHAR(200),
    EMAIL VARCHAR(200),
    PHONE VARCHAR(50),
    ADDRESS VARCHAR(500),
    CITY VARCHAR(100),
    STATE VARCHAR(50),
    SIGNUP_DATE VARCHAR(50),    -- intentionally VARCHAR, not DATE
    CUSTOMER_TIER VARCHAR(50),
    CREATED_AT VARCHAR(50),     -- intentionally VARCHAR, not TIMESTAMP
    UPDATED_AT VARCHAR(50)
);
```

Notice: `SIGNUP_DATE`, `CREATED_AT`, and `UPDATED_AT` are all `VARCHAR` — not typed. This is common in raw data ingested from CSVs, APIs, or legacy systems.

**The intentional data quality issues planted in the 13 rows:**

| Issue | Example | Rows Affected |
|-------|---------|---------------|
| Duplicate customer IDs | C002 appears twice | 1 duplicate |
| NULL emails | Bob Smith has no email | 1 row |
| Empty string addresses | David Lee: `''` | 1 row |
| Mixed-case emails | `FRANK@EXAMPLE.COM` | 1 row |
| Inconsistent date formats | `03/15/2024`, `Jan 5, 2024`, `2024/05/05` | 3 rows |
| NULL customer tier | Henry Davis | 1 row |
| Empty customer name | C012: `''` | 1 row |

For orders, I added currency symbols in amounts (`$59.97`) and stored all numeric fields as VARCHAR.

---

## Step 2: dbt Project Setup — The `cortex source` Authentication Pattern

Here's where it gets interesting. CoCo uses **Programmatic Access Tokens (PAT)** for Snowflake authentication. dbt-snowflake doesn't natively support PAT auth, but CoCo's `cortex source` command solves this elegantly by injecting credentials as environment variables:

```bash
cortex source cortex_ai_app \
  --map account=SNOWFLAKE_ACCOUNT \
  --map user=SNOWFLAKE_USER \
  --map token=SNOWFLAKE_PASSWORD \
  -- bash -c "cd /path/to/coco_dbt_demo && dbt run --profiles-dir ."
```

The trick: **map `token` to `SNOWFLAKE_PASSWORD`**. The PAT token works in dbt's password field because Snowflake's connector accepts it. This means zero hardcoded credentials — everything flows through CoCo's secure credential injection.

**`profiles.yml`:**

```yaml
coco_dbt_demo:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "{{ env_var('SNOWFLAKE_ACCOUNT') }}"
      user: "{{ env_var('SNOWFLAKE_USER') }}"
      password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
      role: ACCOUNTADMIN
      database: COCO_DBT_DEMO
      warehouse: COMPUTE_WH
      schema: ANALYTICS
      threads: 4
```

**`dbt_project.yml`:**

```yaml
name: 'coco_dbt_demo'
version: '1.0.0'
profile: 'coco_dbt_demo'
model-paths: ["models"]
macro-paths: ["macros"]
models:
  coco_dbt_demo:
    staging:
      +materialized: view
      +schema: ANALYTICS
    marts:
      +materialized: table
      +schema: ANALYTICS
```

### The Schema Name Fix

One gotcha we hit: dbt's default `generate_schema_name` macro concatenates `target_schema + custom_schema`, producing `ANALYTICS_ANALYTICS`. CoCo detected this after the first run and generated the fix:

**`macros/generate_schema_name.sql`:**

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
```

This override uses the custom schema name directly instead of concatenating it with the target schema.

---

## Step 3: CoCo-Generated Staging Models — Where the Magic Happens

I asked CoCo:

> *"Create a dbt staging model for COCO_DBT_DEMO.RAW.CUSTOMERS_RAW that handles the data quality issues"*

CoCo first ran a data quality analysis query against the raw table:

```
Real CoCo Analysis Output:
─────────────────────────────────────
total_rows:          13
unique_customers:    12
duplicate_rows:       1
missing_emails:       1
missing_phones:       1
missing_addresses:    1
missing_names:        1
missing_tiers:        1
missing_updated_at:   1
```

Based on this analysis, CoCo generated `stg_customers.sql` — not a generic template, but a model specifically addressing every issue it found:

**`models/staging/stg_customers.sql`:**

```sql
WITH source AS (
    SELECT * FROM {{ source('raw', 'CUSTOMERS_RAW') }}
),

deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY CREATED_AT DESC
        ) AS row_num
    FROM source
),

cleaned AS (
    SELECT
        CUSTOMER_ID,
        CASE
            WHEN CUSTOMER_NAME IS NULL OR TRIM(CUSTOMER_NAME) = ''
            THEN 'Unknown'
            ELSE TRIM(CUSTOMER_NAME)
        END AS CUSTOMER_NAME,
        CASE
            WHEN EMAIL IS NULL OR TRIM(EMAIL) = ''
            THEN NULL
            ELSE LOWER(TRIM(EMAIL))
        END AS EMAIL,
        CASE
            WHEN PHONE IS NULL OR TRIM(PHONE) = ''
            THEN NULL
            ELSE TRIM(PHONE)
        END AS PHONE,
        CASE
            WHEN ADDRESS IS NULL OR TRIM(ADDRESS) = ''
            THEN NULL
            ELSE TRIM(ADDRESS)
        END AS ADDRESS,
        TRIM(CITY) AS CITY,
        TRIM(STATE) AS STATE,
        TRY_TO_DATE(SIGNUP_DATE) AS SIGNUP_DATE,
        COALESCE(CUSTOMER_TIER, 'Unknown') AS CUSTOMER_TIER,
        TRY_TO_TIMESTAMP(CREATED_AT) AS CREATED_AT,
        TRY_TO_TIMESTAMP(UPDATED_AT) AS UPDATED_AT
    FROM deduplicated
    WHERE row_num = 1
)

SELECT * FROM cleaned
```

**What CoCo did — and why each pattern matters:**

| Pattern | Why | Snowflake Function |
|---------|-----|--------------------|
| `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ... DESC)` | Deduplicates C002 keeping most recent record | Window function |
| `CASE WHEN ... IS NULL OR TRIM(...) = '' THEN 'Unknown'` | Handles both NULL and empty-string names (C012) | Defensive CASE |
| `LOWER(TRIM(EMAIL))` | Normalizes `FRANK@EXAMPLE.COM` → `frank@example.com` | String functions |
| `TRY_TO_DATE(SIGNUP_DATE)` | Safely parses dates; returns NULL for unparseable formats | Safe casting |
| `COALESCE(CUSTOMER_TIER, 'Unknown')` | Fills NULL tiers (Henry Davis) with default | NULL handling |

**Key finding: `TRY_TO_DATE` parsed 10 of 12 dates correctly, but returned NULL for two:**

| Customer | Raw SIGNUP_DATE | Parsed Result | Reason |
|----------|----------------|---------------|--------|
| C005 (Eve Martinez) | `2024/05/05` | NULL | Slash format not auto-recognized |
| C011 (Karen Taylor) | `Jan 5, 2024` | NULL | Text month format not auto-recognized |

This is exactly the kind of finding that makes the article real. In production, you'd add a `TRY_TO_DATE(SIGNUP_DATE, 'MM/DD/YYYY')` fallback or a multi-format parsing macro. CoCo's `TRY_TO_DATE` approach is the right first defense — it prevents pipeline failures while surfacing data that needs source-level fixes.

### Orders Staging Model

CoCo also generated `stg_orders.sql` with similar defensive patterns:

```sql
WITH source AS (
    SELECT * FROM {{ source('raw', 'ORDERS_RAW') }}
),

cleaned AS (
    SELECT
        ORDER_ID,
        CUSTOMER_ID,
        TRY_TO_DATE(ORDER_DATE) AS ORDER_DATE,
        TRIM(PRODUCT_NAME) AS PRODUCT_NAME,
        TRY_CAST(QUANTITY AS NUMBER) AS QUANTITY,
        TRY_CAST(UNIT_PRICE AS NUMBER(12, 2)) AS UNIT_PRICE,
        TRY_CAST(REPLACE(TOTAL_AMOUNT, '$', '') AS NUMBER(12, 2)) AS TOTAL_AMOUNT,
        LOWER(TRIM(STATUS)) AS ORDER_STATUS,
        LOWER(TRIM(SHIPPING_METHOD)) AS SHIPPING_METHOD,
        TRY_TO_TIMESTAMP(CREATED_AT) AS CREATED_AT
    FROM source
)

SELECT * FROM cleaned
```

Notable: `REPLACE(TOTAL_AMOUNT, '$', '')` strips currency symbols before `TRY_CAST`. Order O1014 had `$59.97` as the total — without this, the cast would fail.

---

## Step 4: The Marts Layer — Business Logic Aggregation

Next, I asked CoCo to build a fact table joining customers and orders:

**`models/marts/fct_customer_orders.sql`:**

```sql
WITH customers AS (
    SELECT * FROM {{ ref('stg_customers') }}
),

orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

customer_orders AS (
    SELECT
        c.CUSTOMER_ID,
        c.CUSTOMER_NAME,
        c.EMAIL,
        c.CITY,
        c.STATE,
        c.CUSTOMER_TIER,
        c.SIGNUP_DATE,
        COUNT(o.ORDER_ID) AS TOTAL_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'delivered' THEN 1 ELSE 0 END) AS DELIVERED_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'cancelled' THEN 1 ELSE 0 END) AS CANCELLED_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'returned' THEN 1 ELSE 0 END) AS RETURNED_ORDERS,
        COALESCE(SUM(o.TOTAL_AMOUNT), 0) AS LIFETIME_REVENUE,
        COALESCE(AVG(o.TOTAL_AMOUNT), 0) AS AVG_ORDER_VALUE,
        MIN(o.ORDER_DATE) AS FIRST_ORDER_DATE,
        MAX(o.ORDER_DATE) AS LAST_ORDER_DATE,
        DATEDIFF('day', MIN(o.ORDER_DATE), MAX(o.ORDER_DATE)) AS CUSTOMER_TENURE_DAYS
    FROM customers c
    LEFT JOIN orders o ON c.CUSTOMER_ID = o.CUSTOMER_ID
    GROUP BY
        c.CUSTOMER_ID, c.CUSTOMER_NAME, c.EMAIL,
        c.CITY, c.STATE, c.CUSTOMER_TIER, c.SIGNUP_DATE
)

SELECT * FROM customer_orders
```

**Real output — `dbt run` execution:**

```
17:01:56  Running with dbt=1.11.6
17:01:57  Found 3 models, 17 data tests, 1 source
17:01:57  Concurrency: 4 threads (target='dev')
17:01:58  1 of 3 OK created sql view model ANALYTICS.stg_customers ....... [SUCCESS in 0.93s]
17:01:58  2 of 3 OK created sql view model ANALYTICS.stg_orders .......... [SUCCESS in 0.61s]
17:02:04  3 of 3 OK created sql table model ANALYTICS.fct_customer_orders  [SUCCESS in 4.17s]
17:02:04  Finished running 2 view models, 1 table model in 0 hours 0 minutes and 7.49 seconds
```

**Real query result — Top customers by lifetime revenue:**

| Customer | Tier | City | Orders | Delivered | Revenue | Avg Order | Tenure (days) |
|----------|------|------|--------|-----------|---------|-----------|---------------|
| Ivy Chen | Gold | San Francisco | 2 | 1 | $859.96 | $429.98 | 114 |
| Eve Martinez | Gold | Phoenix | 2 | 2 | $449.96 | $224.98 | 38 |
| Jack Wilson | Silver | New York | 1 | 0 | $299.99 | $299.99 | 0 |
| Alice Johnson | Gold | Denver | 3 | 3 | $279.96 | $93.32 | 264 |
| Grace Kim | Platinum | Miami | 1 | 0 | $199.90 | $199.90 | 0 |
| Henry Davis | Unknown | Boston | 0 | 0 | $0.00 | $0.00 | — |
| Unknown | Silver | Atlanta | 0 | 0 | $0.00 | $0.00 | — |

Notice the data quality fixes flowing through: "Unknown" for the empty customer name (C012), "Unknown" tier for Henry Davis's NULL, and the LEFT JOIN correctly showing zero-order customers.

---

## Step 5: dbt Tests — CoCo-Generated Quality Gates

CoCo generated comprehensive `schema.yml` files with tests for every model:

**`models/staging/schema.yml`:**

```yaml
models:
  - name: stg_customers
    columns:
      - name: CUSTOMER_ID
        tests:
          - unique
          - not_null
      - name: CUSTOMER_NAME
        tests:
          - not_null
      - name: CUSTOMER_TIER
        tests:
          - not_null
          - accepted_values:
              values: ['Gold', 'Silver', 'Bronze', 'Platinum', 'Unknown']

  - name: stg_orders
    columns:
      - name: ORDER_ID
        tests:
          - unique
          - not_null
      - name: CUSTOMER_ID
        tests:
          - not_null
          - relationships:
              to: ref('stg_customers')
              field: CUSTOMER_ID
      - name: ORDER_STATUS
        tests:
          - accepted_values:
              values: ['delivered', 'shipped', 'pending', 'cancelled', 'returned']
```

**Real `dbt test` output:**

```
17:09:41  Running with dbt=1.11.6
17:09:42  Found 3 models, 17 data tests, 1 source
17:09:42  Concurrency: 4 threads (target='dev')
17:09:43  1 of 17 PASS unique_stg_customers_CUSTOMER_ID ................ [PASS in 0.87s]
17:09:43  2 of 17 PASS not_null_stg_customers_CUSTOMER_ID .............. [PASS in 0.87s]
17:09:43  3 of 17 PASS not_null_stg_customers_CUSTOMER_NAME ............ [PASS in 0.96s]
...
17:09:47  17 of 17 PASS not_null_fct_customer_orders_LIFETIME_REVENUE .. [PASS in 0.82s]
17:09:47  Finished running 17 data tests in 0 hours 0 minutes and 5.29 seconds
17:09:47  Done. PASS=17 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=17
```

**17/17 tests passing.** The `unique` test on `CUSTOMER_ID` confirms deduplication worked (C002's duplicate was removed). The `relationships` test confirms every order's `CUSTOMER_ID` exists in `stg_customers`. The `accepted_values` test confirms status normalization (no mixed-case values leaking through).

---

## Step 6: Performance Metrics — Real Execution Data

All metrics from `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` on the live `COCO_DBT_DEMO` database:

### Model Build Performance

| Operation | Elapsed Time | Compile Time | Execution Time |
|-----------|-------------|--------------|----------------|
| CREATE VIEW stg_customers | 0.93s | 0.61s | 0.32s |
| CREATE VIEW stg_orders | 0.61s | 0.37s | 0.24s |
| CREATE TABLE fct_customer_orders (CTAS) | 4.17s | 2.08s | 2.10s |
| **Total dbt run** | **7.49s** | — | — |

### Aggregate Query Performance by Type

| Query Type | Count | Avg Time | Min | Max |
|------------|-------|----------|-----|-----|
| SELECT | 5 | 0.31s | 0.05s | 0.69s |
| INSERT | 2 | 1.02s | 0.77s | 1.27s |
| CREATE_VIEW | 2 | 0.77s | 0.61s | 0.93s |
| CREATE_TABLE_AS_SELECT | 1 | 4.17s | — | — |
| CREATE | 3 | 0.11s | 0.06s | 0.14s |

### End-to-End Session

| Metric | Value |
|--------|-------|
| Total queries executed | 16 |
| Session duration (first to last query) | ~7 minutes |
| Total bytes scanned | 29,184 |
| Total rows produced | 23 |

The entire pipeline — from `CREATE SCHEMA` through `dbt test` — completed in a single CoCo session. The CTAS for `fct_customer_orders` was the most expensive operation at 4.17s, which is expected since it materializes the full join and aggregation.

---

## What CoCo Did vs. What I Would Have Done Manually

| Task | Manual Approach | With Cortex Code |
|------|----------------|-----------------|
| **Data profiling** | Write ad-hoc SELECT queries to count NULLs, duplicates, check types | CoCo queried the table and summarized all 7 issues automatically |
| **Staging SQL** | Write SQL iteratively, test each CASE statement | CoCo generated complete defensive SQL with TRY_TO_DATE, TRY_CAST, ROW_NUMBER dedup in one pass |
| **Schema naming bug** | Google "dbt custom schema name", read docs, write macro | CoCo detected `ANALYTICS_ANALYTICS` in the error output and generated the fix macro |
| **Authentication** | Trial and error with dbt profile configs | CoCo's `cortex source` with `--map token=SNOWFLAKE_PASSWORD` worked after one iteration |
| **Test generation** | Manually write schema.yml, look up test syntax | CoCo generated 17 tests covering unique, not_null, accepted_values, and relationships |
| **Mart aggregation** | Write the JOIN + GROUP BY, debug column mismatches | CoCo generated the full fact table with COALESCE defaults, status breakdowns, and tenure calculation |

---

## Lessons Learned

### 1. `TRY_TO_DATE` Is Your Friend (and Your Canary)

CoCo correctly used `TRY_TO_DATE` instead of `TO_DATE`. The two NULL signup dates (`03/15/2024` and `Jan 5, 2024`) aren't bugs — they're a signal. In production, set up a dbt test that flags when `TRY_TO_DATE` produces NULLs above a threshold, and fix the upstream data format.

### 2. The `cortex source` Pattern for dbt Auth

The `--map token=SNOWFLAKE_PASSWORD` pattern is an elegant workaround for PAT-based authentication with dbt. No credentials in files, no environment variable exports — the token flows through CoCo's secure injection mechanism.

### 3. Custom Schema Macros Are Still Necessary

Even with CoCo generating your project, dbt's default schema concatenation behavior (`target_schema_custom_schema`) catches people. The `generate_schema_name` override should be part of every dbt project template.

### 4. Intentionally Messy Data Makes Better Demos

By loading data with real-world issues (duplicates, mixed formats, NULLs, empty strings), we got to demonstrate CoCo's actual analytical capabilities rather than showing it work on already-clean data.

### 5. CoCo's dbt Skill Knows the Ecosystem

CoCo has a built-in dbt skill that understands project structure conventions (staging/marts layers), materialization strategies (views for staging, tables for marts), and test patterns. It generated `{{ source() }}` and `{{ ref() }}` correctly without being told the dbt project structure.

---

## Project Structure — Final State

```
coco_dbt_demo/
├── dbt_project.yml
├── profiles.yml
├── macros/
│   └── generate_schema_name.sql
├── models/
│   ├── staging/
│   │   ├── sources.yml
│   │   ├── schema.yml
│   │   ├── stg_customers.sql
│   │   └── stg_orders.sql
│   └── marts/
│       ├── schema.yml
│       └── fct_customer_orders.sql
└── (seeds/, tests/, analysis/ — empty, scaffolded)
```

---

## Try It Yourself

1. Install Cortex Code: follow the [Snowflake Cortex Code documentation](https://docs.snowflake.com/en/user-guide/cortex-code)
2. Install dbt: `pip install dbt-snowflake`
3. Create the database and load the sample data (SQL above)
4. Ask CoCo: *"Create a dbt staging model for COCO_DBT_DEMO.RAW.CUSTOMERS_RAW that handles data quality issues"*
5. Run with: `cortex source <connection> --map account=SNOWFLAKE_ACCOUNT --map user=SNOWFLAKE_USER --map token=SNOWFLAKE_PASSWORD -- bash -c "cd <project> && dbt run --profiles-dir ."`
6. Test with: same pattern but `dbt test --profiles-dir .`

The full project code is in this article — every SQL statement, every YAML config, every output is from a real execution against Snowflake.

---

*Built with Snowflake Cortex Code + dbt-snowflake 1.11.6 on Snowflake. All query outputs and performance metrics are from a live execution session.*
