defmodule EctoFoundationDB.Layer.Tx.Policy.Tenant do
  @moduledoc false
  # A transaction bound to one tenant. Work inside it must belong to that same
  # tenant, so that a struct or query carrying a foreign prefix is caught instead
  # of being written into the wrong keyspace.
  alias EctoFoundationDB.Exception.IncorrectTenancy
  alias EctoFoundationDB.Layer.Tx.Context
  alias EctoFoundationDB.Layer.Tx.Policy
  alias EctoFoundationDB.Tenant
  alias EctoFoundationDB.Tenant.DirectoryTenant
  alias EctoFoundationDB.Tenant.ManagedTenant

  @behaviour Policy

  @impl true
  def txobj(%Context{tenant: tenant}), do: Tenant.txobj(tenant)

  @impl true
  def join!(ambient = %Context{tenant: tenant}, %Context{
        policy: __MODULE__,
        tenant: tenant
      }),
      do: ambient

  # Dropping to the database scope is allowed when this tenant already writes its
  # keys through the database itself, which is to say a DirectoryTenant. It gives
  # the nested work a scope that can span tenants. A ManagedTenant is rejected here
  # for the same reason it cannot join a database transaction.
  def join!(ambient = %Context{tenant: tenant}, incoming = %Context{policy: Policy.Db, db: db}) do
    if Tenant.txobj(tenant) == db do
      %{incoming | tx: ambient.tx}
    else
      raise IncorrectTenancy, """
      FoundationDB Adapter encountered a transaction on the tenant #{inspect(tenant)} that \
      cannot be shared with work on the database #{inspect(db)}.

      A transaction on a tenant can only be joined by work on that tenant's own database, \
      and only when the tenant uses the #{inspect(DirectoryTenant)} backend. A \
      #{inspect(ManagedTenant)} holds its own transaction context, so work within it must \
      name the tenant.
      """
    end
  end

  def join!(%Context{tenant: ambient_tenant}, %Context{policy: __MODULE__, tenant: tenant}) do
    raise IncorrectTenancy, """
    FoundationDB Adapter encountered a transaction where the original transaction context \
    #{inspect(ambient_tenant)} did not match the prefix on a struct or query within the transaction: \
    #{inspect(tenant)}.

    This can be encountered when a struct read from one tenant is provided to a transaction from \
    another. In these cases, the prefix must explicitly be removed from the struct metadata.
    """
  end

  @impl true
  def fetch_tenant(%Context{tenant: tenant}, nil), do: {:ok, tenant}

  def fetch_tenant(ambient, prefix), do: {:ok, join!(ambient, Context.new(prefix)).tenant}
end
