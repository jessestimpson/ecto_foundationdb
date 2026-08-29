defmodule EctoFoundationDB.Layer.Tx.Context do
  @moduledoc false
  # The transactional context of the calling process: which transaction is open, and
  # under what policy the work inside it is allowed to happen. There is exactly one
  # context in the process dictionary at a time. Nesting swaps it and puts back what
  # it displaced, so an inner scope can never strip the outer one of its context.
  alias EctoFoundationDB.Database
  alias EctoFoundationDB.Layer.Tx.Context
  alias EctoFoundationDB.Layer.Tx.Policy
  alias EctoFoundationDB.Tenant

  defstruct [:policy, :tenant, :db, :tx]

  @type t() :: %Context{
          policy: module(),
          tenant: Tenant.t() | nil,
          db: Database.t() | nil,
          tx: :erlfdb.transaction() | nil
        }

  @key :__ectofdbtx__

  @spec new(Tenant.t() | Database.t()) :: t()
  def new(tenant = %Tenant{}), do: %Context{policy: Policy.Tenant, tenant: tenant}
  def new(db = {:erlfdb_database, _}), do: %Context{policy: Policy.Db, db: db}

  @spec current() :: t() | nil
  def current(), do: Process.get(@key)

  @doc """
  Installs `context` and returns the one it displaced, to be given to `restore/1`.
  """
  @spec enter(t()) :: t() | nil
  def enter(context = %Context{}), do: Process.put(@key, context)

  @spec restore(t() | nil) :: :ok
  def restore(nil), do: then(Process.delete(@key), fn _ -> :ok end)
  def restore(context = %Context{}), do: then(Process.put(@key, context), fn _ -> :ok end)

  @spec tx() :: :erlfdb.transaction() | nil
  def tx() do
    case current() do
      nil -> nil
      %Context{tx: tx} -> tx
    end
  end

  @spec tenant() :: Tenant.t() | nil
  def tenant() do
    case current() do
      %Context{policy: Policy.Tenant, tenant: tenant} -> tenant
      _ -> nil
    end
  end

  @spec txobj(t()) :: Policy.txobj()
  def txobj(context = %Context{policy: policy}), do: policy.txobj(context)

  @doc """
  Answers what context the work described by `incoming` runs under, given that
  `ambient` is already open. Raises if the two cannot share a transaction.
  """
  @spec join!(t(), t()) :: t()
  def join!(ambient = %Context{policy: policy}, incoming = %Context{}),
    do: policy.join!(ambient, incoming)

  @doc """
  The tenant that one operation runs on: the `:prefix` the caller provided, else the
  one the open transaction is bound to. `:error` when there is neither.
  """
  @spec fetch_tenant(Tenant.t() | nil) :: {:ok, Tenant.t()} | :error
  def fetch_tenant(prefix) do
    case current() do
      nil -> :error
      context = %Context{policy: policy} -> policy.fetch_tenant(context, prefix)
    end
  end
end
