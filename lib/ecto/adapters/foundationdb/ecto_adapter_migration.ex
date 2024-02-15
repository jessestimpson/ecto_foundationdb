defmodule Ecto.Adapters.FoundationDB.EctoAdapterMigration do
  @moduledoc """
  Ecto.Adapter.Migration lives in ecto_sql, so it has SQL behavior baked in.
  We'll do our best to translate into FoundationDB operations so that migrations
  are minimally usable. The experience might feel a little strange though.
  """
  @behaviour Ecto.Adapter.Migration

  alias Ecto.Adapters.FoundationDB, as: FDB
  alias Ecto.Adapters.FoundationDB.Tenant
  alias Ecto.Adapters.FoundationDB.Layer.IndexInventory
  # alias Ecto.Adapters.FoundationDB.Layer.Tx

  @migration_keyspace_prefix <<0xFE>>

  def prepare_source(k = "schema_migrations"),
    do: {:ok, {prepare_migration_key(k), [usetenant: true]}}

  def prepare_source(_k), do: {:error, :unknown_source}

  def prepare_migration_key(key), do: "#{@migration_keyspace_prefix <> key}"

  @impl true
  def supports_ddl_transaction?() do
    # TODO: maybe support this?
    false
  end

  @impl true
  def execute_ddl(
        _adapter_meta = %{opts: _adapter_opts},
        {:create_if_not_exists,
         %Ecto.Migration.Table{
           name: :schema_migrations,
           primary_key: true
         },
         [
           {:add, :version, :bigint, [primary_key: true]},
           {:add, :inserted_at, :naive_datetime, []}
         ]},
        _options
      ) do
    {:ok, [{}]}
  end

  def execute_ddl(
        adapter_meta = %{opts: adapter_opts},
        {:create,
         %Ecto.Migration.Index{
           prefix: tenant_id,
           table: source,
           name: index_name,
           columns: index_fields
         }},
        _options
      )
      when is_binary(tenant_id) do
    db = FDB.db(adapter_opts)
    tenant = Tenant.open!(db, tenant_id, adapter_opts)
    :ok = IndexInventory.create_index(tenant, adapter_meta, source, index_name, index_fields)
    {:ok, []}
  end

  @impl true
  def lock_for_migrations(_adapter_meta = %{opts: _adapter_opts}, _options, fun) do
    # Ecto wants to lock the `schema_migrations` table when running
    # migrations, guaranteeing two different servers cannot run the same
    # migration at the same time.
    #
    # Unfortunately, the mechanism it uses isn't compatible with the design of :erlfdb.
    # We've attempted to start a transaction on the tenant and add a write conflict on
    # all the keys in the tenant. Then, the migration would run fully within that transaction.
    #
    # However, Ecto.Migrator.async_migrate_maybe_in_transaction/7 uses a Task to
    # perform the ddl steps. The use of the Task breaks our transaction because the Task
    # has its own process dictionary, and we cannot telegraph the transaction handle
    # to the ddl. I'm unsure how we can resolve this without a change to ecto_sql. For
    # now, we just don't lock. It will be up to the application to ensure there are no
    # conflicts when running migrations on tenants.

    fun.()
  end
end
