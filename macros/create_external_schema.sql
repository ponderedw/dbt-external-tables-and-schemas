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

  Configuration (in priority order):
    1. external.meta in sources YAML:
         external:
           meta:
             database: my_glue_db
             iam_role: arn:aws:iam::123456789012:role/MyRole
    2. config.meta in sources YAML:
         config:
           meta:
             database: my_glue_db
             iam_role: arn:aws:iam::123456789012:role/MyRole
    3. Project vars:
         vars:
           ext_database: my_glue_db
           ext_iam_role: arn:aws:iam::123456789012:role/MyRole
    4. Environment variables:
         DBT_EXT_DATABASE, DBT_EXT_IAM_ROLE
#}
{%- macro redshift__create_external_schema(source_node) -%}

    {%- set ext = source_node.external | default({}) -%}
    {%- set ext_meta = ext.meta | default({}) -%}
    {%- set config_meta = source_node.config.meta | default({}) -%}

    {%- set database = ext_meta.database | default('')
        or config_meta.database | default('')
        or var('ext_database', '')
        or env_var('DBT_EXT_DATABASE', '') -%}

    {%- set iam_role = ext_meta.iam_role | default('')
        or config_meta.iam_role | default('')
        or var('ext_iam_role', '')
        or env_var('DBT_EXT_IAM_ROLE', '') -%}

    {%- if not database -%}
        {{ exceptions.raise_compiler_error(
            "dbt_external_tables_and_schemas: 'database' is required to create external schema '"
            ~ source_node.schema ~ "'. Set it via external.meta.database, config.meta.database, "
            ~ "the 'ext_database' var, or the DBT_EXT_DATABASE env var."
        ) }}
    {%- endif -%}

    {%- if not iam_role -%}
        {{ exceptions.raise_compiler_error(
            "dbt_external_tables_and_schemas: 'iam_role' is required to create external schema '"
            ~ source_node.schema ~ "'. Set it via external.meta.iam_role, config.meta.iam_role, "
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
