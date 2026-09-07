{% macro stage_external_sources(select=none) %}

    {#
      Step 1: Create external schemas for all selected external sources (deduplicated by schema).
      Step 2: Delegate table staging to the original dbt_external_tables package.

      This macro shadows dbt_external_tables.stage_external_sources so users run the same command:
        dbt run-operation stage_external_sources
        dbt run-operation stage_external_sources --args "select: snowplow.event"
    #}

    {% if execute %}

        {% set schemas_created = [] %}
        {% set source_nodes = graph.sources.values() if graph.sources else [] %}
        {% set stmt_counter = namespace(value=0) %}

        {% for node in source_nodes %}
            {% if node.external %}

                {# Mirror the selection logic from dbt_external_tables.stage_external_sources #}
                {% set selected = namespace(value=(select is none)) %}
                {% if select %}
                    {% for src in select.split(' ') %}
                        {% if '.' in src %}
                            {% set parts = src.split('.') %}
                            {% if parts[0] == node.source_name and parts[1] == node.name %}
                                {% set selected.value = true %}
                            {% endif %}
                        {% else %}
                            {% if src == node.source_name %}
                                {% set selected.value = true %}
                            {% endif %}
                        {% endif %}
                    {% endfor %}
                {% endif %}

                {% if selected.value and node.schema not in schemas_created %}

                    {% do schemas_created.append(node.schema) %}
                    {% set stmt_counter.value = stmt_counter.value + 1 %}

                    {% set schema_ddl = dbt_external_tables_and_schemas.create_external_schema(node) %}
                    {% do log('Creating external schema if not exists: ' ~ node.schema, info=true) %}

                    {% set exit_txn = dbt_external_tables.exit_transaction() %}
                    {% call statement('create_ext_schema_' ~ stmt_counter.value, fetch_result=False, auto_begin=False) %}
                        {{ exit_txn }} {{ schema_ddl }}
                    {% endcall %}

                {% endif %}

            {% endif %}
        {% endfor %}

    {% endif %}

    {# Step 2: run the original package's table staging #}
    {{ dbt_external_tables.stage_external_sources(select=select) }}

{% endmacro %}
