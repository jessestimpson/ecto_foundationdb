defmodule EctoFoundationDB.Layer.Tx.Policy.Db do
  @moduledoc false
  # A transaction bound to a database, with no tenant of its own. Tenants of that
  # database join it as the work requires, which is what lets one transaction span
  # the tenants of several Repos.
  alias EctoFoundationDB.Exception.IncorrectTenancy
  alias EctoFoundationDB.Layer.Tx.Context
  alias EctoFoundationDB.Layer.Tx.Policy
  alias EctoFoundationDB.Tenant
  alias EctoFoundationDB.Tenant.DirectoryTenant
  alias EctoFoundationDB.Tenant.ManagedTenant

  @behaviour Policy

  @impl true
  def txobj(%Context{db: db}), do: db

  # A joining tenant must write its keys through this transaction object. A
  # DirectoryTenant's txobj is the database itself, so this equality also rejects a
  # ManagedTenant, whose keys are prefixed by FDB at the transaction level instead.
  @impl true
  def join!(
        ambient = %Context{db: db},
        incoming = %Context{policy: Policy.Tenant, tenant: tenant}
      ) do
    if Tenant.txobj(tenant) == db do
      %Context{incoming | db: db, tx: ambient.tx}
    else
      raise IncorrectTenancy, """
      FoundationDB Adapter encountered a database-level transaction that cannot be shared with \
      the tenant #{inspect(tenant)}.

      A transaction opened on a database can only be joined by tenants of that same database, \
      and only when they use the #{inspect(DirectoryTenant)} backend. A #{inspect(ManagedTenant)} \
      holds its own transaction context, so it must use `Repo.transactional/2` instead.
      """
    end
  end

  def join!(ambient = %Context{db: db}, %Context{policy: __MODULE__, db: db}), do: ambient

  def join!(%Context{db: db}, %Context{policy: __MODULE__, db: other}) do
    raise IncorrectTenancy, """
    FoundationDB Adapter encountered a transaction on the database #{inspect(db)} that cannot \
    be shared with work on the database #{inspect(other)}.

    A transaction belongs to a single database. All Repos taking part in it must be configured \
    with the same `:cluster_file`.
    """
  end

  @impl true
  def fetch_tenant(_context, nil), do: :error

  def fetch_tenant(ambient, prefix), do: {:ok, join!(ambient, Context.new(prefix)).tenant}
end
