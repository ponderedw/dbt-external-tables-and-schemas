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

The Redshift schema creation requires two values per schema: the **Glue/Lake Formation database name** and the **IAM role ARN**. These can be set at four levels (highest priority wins).

### 1. `external.meta` in sources YAML

Useful when different schemas use different IAM roles or databases.

```yaml
# models/sources.yml
sources:
  - name: snowplow
    schema: spectrum_snowplow
    tables:
      - name: event
        external:
          location: "s3://my-bucket/snowplow/events/"
          meta:
            database: my_glue_database
            iam_role: "arn:aws:iam::123456789012:role/RedshiftSpectrumRole"
          # ... other dbt-external-tables properties
```

### 2. `config.meta` in sources YAML

Applies to all tables under a source entry. Useful for grouping config with the rest of your dbt source metadata.

```yaml
sources:
  - name: snowplow
    schema: spectrum_snowplow
    tables:
      - name: event
        config:
          meta:
            database: my_glue_database
            iam_role: "arn:aws:iam::123456789012:role/RedshiftSpectrumRole"
        external:
          location: "s3://my-bucket/snowplow/events/"
```

All tables sharing the same `schema` must agree on `database` and `iam_role` — the values from the first table encountered are used for schema creation.

### 3. Project vars

Applies to all external schemas in the project.

```yaml
# dbt_project.yml
vars:
  ext_database: my_glue_database
  ext_iam_role: "arn:aws:iam::123456789012:role/RedshiftSpectrumRole"
```

### 4. Environment variables

```bash
export DBT_EXT_DATABASE=my_glue_database
export DBT_EXT_IAM_ROLE=arn:aws:iam::123456789012:role/RedshiftSpectrumRole
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
