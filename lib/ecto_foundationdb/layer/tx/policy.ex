defmodule EctoFoundationDB.Layer.Tx.Policy do
  @moduledoc false
  # A transaction is opened either on a tenant or on a database, and that choice
  # decides two things: what erlfdb object the transaction is opened on, and which
  # nested work may join it. Everything else about a transaction is common, so the
  # process state itself is handled by `EctoFoundationDB.Layer.Tx.Context`.
  alias EctoFoundationDB.Layer.Tx.Context
  alias EctoFoundationDB.Tenant

  @type txobj() :: :erlfdb.database() | :erlfdb.tenant()

  @doc "The erlfdb object that `:erlfdb.transactional/2` is opened on."
  @callback txobj(context :: Context.t()) :: txobj()

  @doc """
  The context that `incoming` work runs under, given that `ambient` is already open.

  Returns `ambient` when the incoming work adds nothing to the context. Raises
  `EctoFoundationDB.Exception.IncorrectTenancy` when the two cannot share a transaction.
  """
  @callback join!(ambient :: Context.t(), incoming :: Context.t()) :: Context.t()

  @doc """
  The tenant that one operation runs on, given the ambient context and the `:prefix`
  the caller provided (`nil` when it provided none).

  Returns `:error` when the context cannot supply a tenant and the caller named none.
  Raises `EctoFoundationDB.Exception.IncorrectTenancy` when the named tenant cannot do
  work in this transaction.
  """
  @callback fetch_tenant(context :: Context.t(), prefix :: Tenant.t() | nil) ::
              {:ok, Tenant.t()} | :error
end
