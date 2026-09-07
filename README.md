# dbt-external-tables-and-schemas

A dbt package that extends [dbt-labs/dbt-external-tables](https://github.com/dbt-labs/dbt-external-tables) with automatic external schema creation before staging external sources.

The original `dbt-external-tables` package can create and refresh external tables, but it cannot create the external schema itself. This package fills that gap: when you run `stage_external_sources`, it first creates any missing external schemas, then delegates table staging to the original package.

Redshift Spectrum is the primary target (requires `CREATE EXTERNAL SCHEMA ... FROM DATA CATALOG`). All other adapters fall back to the original package's behavior.

## Installation

In your project's `packages.yml`, replace any direct dependency on `dbt-external-tables` with this package:

```yaml
packages:
  - package: ponder-data/dbt_external_tables_and_schemas
    version: [">=0.1.0", "<1.0.0"]
```

> Do **not** also list `dbt-labs/dbt_external_tables` — this package brings it in as a dependency.

Run `dbt deps` to install.

## Usage

The commands are identical to the original package:

```bash
# Stage all external sources (creates schemas first)
dbt run-operation stage_external_sources

# Stage a specific source or table
dbt run-operation stage_external_sources --args "select: snowplow"
dbt run-operation stage_external_sources --args "select: snowplow.event"
```

## Configuration

Schema creation requires two values: the **Glue/Lake Formation database name** and the **IAM role ARN**. Both support a prefix pattern so you don't have to repeat the full value in every source file.

### `database`

Priority order (first match wins):

| Level | How to set |
|---|---|
| Per-source explicit | `external.meta.database` or `config.meta.database` in sources YAML |
| Project-wide explicit | `ext_database` var or `DBT_EXT_DATABASE` env var |
| Project-wide prefix | `ext_database_prefix` var or `DBT_EXT_DATABASE_PREFIX` env var → database = `{prefix}_{schema}` |

**Prefix pattern** (most common — one setting covers all schemas):
```yaml
# dbt_project.yml
vars:
  ext_database_prefix: "aws_database_production"
```
Schema `external_tables_qualtrics` → database `aws_database_production_external_tables_qualtrics`.

### `iam_role`

Priority order (first match wins):

| Level | How to set |
|---|---|
| Per-source explicit | `external.meta.iam_role` or `config.meta.iam_role` in sources YAML |
| Project-wide default | `ext_iam_role` var or `DBT_EXT_IAM_ROLE` env var (full ARN) |

`config.meta.iam_role` accepts either a **full ARN** (used as-is) or a **short role name**, which is expanded using `ext_iam_role_prefix` var / `DBT_EXT_IAM_ROLE_PREFIX` env var:

```yaml
# dbt_project.yml
vars:
  ext_iam_role_prefix: "arn:aws:iam::123456789012:role"
```
```yaml
# sources YAML — per-source short name
sources:
  - name: my_source
    tables:
      - name: my_table
        config:
          meta:
            iam_role: "my_spectrum_role"
        external:
          location: "s3://..."
```
→ `arn:aws:iam::123456789012:role/my_spectrum_role`

Sources without a `config.meta.iam_role` fall back to `ext_iam_role` / `DBT_EXT_IAM_ROLE`.

### Typical project setup

```yaml
# dbt_project.yml
vars:
  ext_database_prefix: "aws_database_production"       # or use env var DBT_EXT_DATABASE_PREFIX
  ext_iam_role_prefix: "arn:aws:iam::123456789012:role" # or use env var DBT_EXT_IAM_ROLE_PREFIX
  ext_iam_role: "arn:aws:iam::123456789012:role/DefaultSpectrumRole"  # fallback for sources without iam_role
```

## What gets executed for Redshift

For each unique schema among the selected external sources, the package runs:

```sql
create external schema if not exists <schema>
from data catalog
database '<database>'
iam_role '<iam_role>'
create external database if not exists
```

If the schema already exists, this is a no-op. After all schemas are ensured, the original `dbt_external_tables.stage_external_sources` runs to create or refresh the tables.

## Non-Redshift adapters

For all other adapters (Snowflake, BigQuery, Spark, etc.), schema creation falls back to `dbt_external_tables.create_external_schema`, which generates a standard `CREATE SCHEMA IF NOT EXISTS` statement. Table staging behavior is unchanged.

## Requirements

- dbt >= 1.0.0
- dbt-labs/dbt_external_tables >= 0.8.0
