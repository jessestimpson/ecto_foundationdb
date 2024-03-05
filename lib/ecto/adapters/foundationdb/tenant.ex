defmodule Ecto.Adapters.FoundationDB.Tenant do
  @moduledoc """
  This module allows the application to manage the creation and deletion of
  tenants within the FoundationDB database. All transactions require a tenant,
  so any application that uses the Ecto FoundationDB Adapter must use this module.
  """

  @type t() :: :erlfdb.tenant()
  @type id() :: :erlfdb.tenant_name()

  alias Ecto.Adapters.FoundationDB, as: FDB
  alias Ecto.Adapters.FoundationDB.Database
  alias Ecto.Adapters.FoundationDB.EctoAdapterStorage
  alias Ecto.Adapters.FoundationDB.Options

  @doc """
  Open a tenant. With the result returned by this function, the caller can
  do database operations on the tenant's portion of the key-value store.
  """
  @spec open!(Ecto.Repo.t(), id()) :: t()
  def open!(repo, id), do: open!(FDB.db(repo), id, repo.config())

  @doc """
  Returns true if the tenant already exists in the database.
  """
  @spec exists?(Ecto.Repo.t(), id()) :: boolean()
  def exists?(repo, id), do: exists?(FDB.db(repo), id, repo.config())

  @doc """
  Open a tenant. With the result returned by this function, the caller can
  do database operations on the tenant's portion of the key-value store.
  """
  @spec open(Ecto.Repo.t(), id()) :: t()
  def open(repo, id), do: open(FDB.db(repo), id, repo.config())

  @doc """
  List all tenants in the database. Could be expensive.
  """
  @spec list(Ecto.Repo.t()) :: [id()]
  def list(repo), do: list(FDB.db(repo), repo.config())

  @doc """
  Create a tenant in the database.
  """
  @spec create(Ecto.Repo.t(), id()) :: :ok
  def create(repo, id), do: create(FDB.db(repo), id, repo.config())

  @doc """
  Clear all data for the given tenant. This cannot be undone.
  """
  @spec clear(Ecto.Repo.t(), id()) :: :ok
  def clear(repo, id), do: clear(FDB.db(repo), id, repo.config())

  @doc """
  Deletes a tenant from the database permanently. The tenant must
  have no data.
  """
  @spec delete(Ecto.Repo.t(), id()) :: :ok
  def delete(repo, id), do: delete(FDB.db(repo), id, repo.config())

  @spec open!(Database.t(), id(), Options.t()) :: t()
  def open!(db, id, options) do
    :ok = ensure_created(db, id, options)
    open(db, id, options)
  end

  @doc """
  Helper function to ensure the given tenant exists and then clear
  it of all data, and finally return an open handle. Useful in test code,
  but in production, this would be dangerous.
  """
  @spec open_empty!(Database.t(), id(), Options.t()) :: t()
  def open_empty!(db, id, options) do
    :ok = ensure_created(db, id, options)
    :ok = empty(db, id, options)
    open(db, id, options)
  end

  @doc """
  Clears data in a tenant and then deletes it. If the tenant doesn't exist, no-op.
  """
  @spec clear_delete!(Database.t(), id(), Options.t()) :: :ok
  def clear_delete!(db, id, options) do
    if exists?(db, id, options) do
      :ok = clear(db, id, options)
      :ok = delete(db, id, options)
    end

    :ok
  end

  @doc """
  If the tenant doesn't exist, create it. Otherwise, no-op.
  """
  @spec ensure_created(Database.t(), id(), Options.t()) :: :ok
  def ensure_created(db, id, options) do
    case exists?(db, id, options) do
      true -> :ok
      false -> create(db, id, options)
    end
  end

  @doc """
  Returns true if the tenant exists in the database. False otherwise.
  """
  @spec exists?(Database.t(), id(), Options.t()) :: boolean()
  def exists?(db, id, options), do: EctoAdapterStorage.tenant_exists?(db, id, options)

  @spec open(Database.t(), id(), Options.t()) :: t()
  def open(db, id, options), do: EctoAdapterStorage.open_tenant(db, id, options)

  @spec list(Database.t(), Options.t()) :: [id()]
  def list(db, options) do
    for {_k, json} <- EctoAdapterStorage.list_tenants(db, options) do
      %{"name" => %{"printable" => name}} = Jason.decode!(json)
      EctoAdapterStorage.tenant_name_to_id!(name, options)
    end
  end

  @spec create(Database.t(), id(), Options.t()) :: :ok
  def create(db, id, options), do: EctoAdapterStorage.create_tenant(db, id, options)

  @spec clear(Database.t(), id(), Options.t()) :: :ok
  def clear(db, id, options), do: EctoAdapterStorage.clear_tenant(db, id, options)

  @spec empty(Database.t(), id(), Options.t()) :: :ok
  def empty(db, id, options), do: EctoAdapterStorage.empty_tenant(db, id, options)

  @spec delete(Database.t(), id(), Options.t()) :: :ok
  def delete(db, id, options), do: EctoAdapterStorage.delete_tenant(db, id, options)
end
