defmodule EctoFoundationDB.Schema do
  @moduledoc false

  alias EctoFoundationDB.Versionstamp

  def get_context!(_source, schema) when is_atom(schema) and not is_nil(schema) do
    %{__meta__: _meta = %{context: context}} = Kernel.struct!(schema)
    context
  end

  def get_context!(_source, _schema), do: []

  def get_source(schema) do
    schema.__schema__(:source)
  end

  def field_types(schema) do
    field_types(schema, schema.__schema__(:fields))
  end

  def field_types(schema, fields) do
    for field <- fields,
        do: {field, schema.__schema__(:type, field)}
  end

  def get_option(context, :write_primary), do: get_option(context, :write_primary, true)

  def get_option(nil, _key, default), do: default
  def get_option(context, key, default), do: Keyword.get(context, key, default)

  @doc false
  def get_partition_by_field(schema, context) when is_atom(schema) and not is_nil(schema) do
    case schema.__schema__(:primary_key) do
      [pk_field | _] ->
        case schema.__schema__(:type, pk_field) do
          {:parameterized, Versionstamp, %{partition_by: p}} when not is_nil(p) -> p
          _ -> get_option(context, :partition_by, nil)
        end

      _ ->
        get_option(context, :partition_by, nil)
    end
  end

  def get_partition_by_field(_schema, context), do: get_option(context, :partition_by, nil)
end
