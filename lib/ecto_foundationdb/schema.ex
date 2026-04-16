defmodule EctoFoundationDB.Schema do
  @moduledoc """
  Drop-in replacement for `use Ecto.Schema` that supports EctoFoundationDB-specific
  options directly in the `@primary_key` attribute.

  ## Partition option

  Schemas with a versionstamp primary key can co-locate records by a partition field
  by adding `partition: :field_name` to `@primary_key`:

      use EctoFoundationDB.Schema

      @primary_key {:id, EctoFoundationDB.Versionstamp, autogenerate: false, partition: :user_id}

      schema "sessions" do
        field :user_id, :string
        field :data, :string
      end

  This is equivalent to the long form using `@schema_context`:

      use Ecto.Schema

      @schema_context [partition: :user_id]
      @primary_key {:id, EctoFoundationDB.Versionstamp, autogenerate: false}

      schema "sessions" do
        ...
      end

  With a partition configured, range queries can be scoped to a single partition
  by passing a `{partition_value, id}` tuple as the primary key parameter:

      Repo.all(from s in Session, where: s.id >= ^{"alice", checkpoint}, prefix: tenant)

  `Repo.delete` and `Repo.update` are not supported for partitioned schemas; use
  `Repo.delete_all` and `Repo.update_all` with an equality constraint instead:

      Repo.delete_all(from s in Session, where: s.id == ^{"alice", id}, prefix: tenant)
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import EctoFoundationDB.Schema, only: [schema: 2]
    end
  end

  @doc false
  defmacro schema(source, do: block) do
    quote do
      # Strip EctoFoundationDB-specific options from @primary_key before Ecto's
      # schema/2 macro reads and validates the pk opts. Ecto rejects unknown opts.
      case Module.get_attribute(__MODULE__, :primary_key) do
        {pk_name, pk_type, pk_opts} when is_list(pk_opts) ->
          case Keyword.pop(pk_opts, :partition) do
            {nil, _} ->
              :ok

            {partition_field, clean_opts} ->
              Module.put_attribute(__MODULE__, :primary_key, {pk_name, pk_type, clean_opts})
              ctx = Module.get_attribute(__MODULE__, :schema_context) || []
              Module.put_attribute(__MODULE__, :schema_context, Keyword.put_new(ctx, :partition, partition_field))
          end

        _ ->
          :ok
      end

      Ecto.Schema.schema(unquote(source)) do
        unquote(block)
      end
    end
  end

  @doc false
  def get_context!(_source, schema) when is_atom(schema) and not is_nil(schema) do
    %{__meta__: _meta = %{context: context}} = Kernel.struct!(schema)
    context
  end

  def get_context!(_source, _schema), do: []

  @doc false
  def get_source(schema) do
    schema.__schema__(:source)
  end

  @doc false
  def field_types(schema) do
    field_types(schema, schema.__schema__(:fields))
  end

  @doc false
  def field_types(schema, fields) do
    for field <- fields,
        do: {field, schema.__schema__(:type, field)}
  end

  @doc false
  def get_option(context, :write_primary), do: get_option(context, :write_primary, true)

  def get_option(nil, _key, default), do: default
  def get_option(context, key, default), do: Keyword.get(context, key, default)

  @doc false
  def get_partition_field(context), do: get_option(context, :partition, nil)
end
