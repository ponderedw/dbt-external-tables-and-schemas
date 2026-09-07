{%- macro create_external_schema(source_node) -%}
    {{ adapter.dispatch('create_external_schema', 'dbt_external_tables_and_schemas')(source_node) }}
{%- endmacro -%}


{#
  Default: delegate to the original package, which handles Snowflake, BigQuery, etc.
  via its own dispatch table (default__create_external_schema → CREATE SCHEMA IF NOT EXISTS).
#}
{%- macro default__create_external_schema(source_node) -%}
    {{ dbt_external_tables.create_external_schema(source_node) }}
{%- endmacro -%}


{#
  Redshift Spectrum: CREATE EXTERNAL SCHEMA IF NOT EXISTS ... FROM DATA CATALOG.

  ── database ─────────────────────────────────────────────────────────────────
  Priority:
    1. external.meta.database or config.meta.database  (explicit, per-source)
    2. ext_database var / DBT_EXT_DATABASE env var      (explicit, project-wide)
    3. ext_database_prefix var / DBT_EXT_DATABASE_PREFIX env var
       → database = "{prefix}_{schema}"               (derived, project-wide)

  Example (prefix pattern):
    vars:
      ext_database_prefix: "glue_db_prod"
    → schema "my_schema" becomes database "glue_db_prod_my_schema"

  ── iam_role ─────────────────────────────────────────────────────────────────
  Priority:
    1. external.meta.iam_role or config.meta.iam_role
       - Full ARN  (starts with "arn:") → used as-is
       - Short name                     → "{ext_iam_role_prefix}/{short_name}"
    2. ext_iam_role var / DBT_EXT_IAM_ROLE env var  (full ARN, project-wide default)

  Example (short name + prefix pattern):
    vars:
      ext_iam_role_prefix: "arn:aws:iam::123456789012:role"
    config.meta.iam_role: "my_spectrum_role"
    → "arn:aws:iam::123456789012:role/my_spectrum_role"
#}
{%- macro redshift__create_external_schema(source_node) -%}

    {%- set ext = source_node.external | default({}) -%}
    {%- set ext_meta = ext.meta | default({}) -%}
    {%- set config_meta = source_node.config.meta | default({}) -%}

    {# ── Resolve database ── #}
    {%- set database_explicit = ext_meta.database | default('')
        or config_meta.database | default('')
        or var('ext_database', '')
        or env_var('DBT_EXT_DATABASE', '') -%}

    {%- set database_prefix = var('ext_database_prefix', '') or env_var('DBT_EXT_DATABASE_PREFIX', '') -%}

    {%- set database = database_explicit or (database_prefix ~ '_' ~ source_node.schema if database_prefix else '') -%}

    {# ── Resolve iam_role ── #}
    {%- set iam_role_raw = ext_meta.iam_role | default('') or config_meta.iam_role | default('') -%}
    {%- set iam_role_prefix = var('ext_iam_role_prefix', '') or env_var('DBT_EXT_IAM_ROLE_PREFIX', '') -%}

    {%- if iam_role_raw -%}
        {%- if iam_role_raw.startswith('arn:') or not iam_role_prefix -%}
            {%- set iam_role = iam_role_raw -%}
        {%- else -%}
            {%- set iam_role = iam_role_prefix ~ '/' ~ iam_role_raw -%}
        {%- endif -%}
    {%- else -%}
        {%- set iam_role = var('ext_iam_role', '') or env_var('DBT_EXT_IAM_ROLE', '') -%}
    {%- endif -%}

    {%- if not database -%}
        {{ exceptions.raise_compiler_error(
            "dbt_external_tables_and_schemas: 'database' is required to create external schema '"
            ~ source_node.schema ~ "'. Set it via external.meta.database, config.meta.database, "
            ~ "the 'ext_database' / 'ext_database_prefix' var, or the DBT_EXT_DATABASE / DBT_EXT_DATABASE_PREFIX env var."
        ) }}
    {%- endif -%}

    {%- if not iam_role -%}
        {{ exceptions.raise_compiler_error(
            "dbt_external_tables_and_schemas: 'iam_role' is required to create external schema '"
            ~ source_node.schema ~ "'. Set it via external.meta.iam_role, config.meta.iam_role (short name or full ARN), "
            ~ "the 'ext_iam_role' var, or the DBT_EXT_IAM_ROLE env var."
        ) }}
    {%- endif -%}

    {%- set ddl -%}
        create external schema if not exists {{ source_node.schema }}
        from data catalog
        database '{{ database }}'
        iam_role '{{ iam_role }}'
        create external database if not exists
    {%- endset -%}

    {{ return(ddl) }}

{%- endmacro -%}
