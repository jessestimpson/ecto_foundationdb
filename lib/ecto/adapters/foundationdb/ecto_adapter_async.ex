defmodule Ecto.Adapters.FoundationDB.EctoAdapterAsync do
  @moduledoc false
  alias Ecto.Adapters.FoundationDB
  alias EctoFoundationDB.Exception.Unsupported
  alias EctoFoundationDB.Layer.Fields
  alias EctoFoundationDB.Future
  alias EctoFoundationDB.Layer.Pack
  alias EctoFoundationDB.Layer.Tx
  alias EctoFoundationDB.Versionstamp
  import Ecto.Query

  def async_insert_all!(_module, repo, schema, list, opts) do
    {tx?, tenant} = Tx.in_tenant_tx?()

    if not tx?,
      do: raise(Unsupported, "async_insert_all! must be called within a transaction")

    pk_field = Fields.get_pk_field!(schema)

    tx = Tx.get()

    result =
      for x <- list do
        # If field is type :id and passed in as null, generate a new versionstamp
        x =
          if is_nil(Map.get(x, pk_field)) and schema.__schema__(:type, pk_field) == :id do
            Map.put(x, pk_field, Versionstamp.next(tx))
          else
            x
          end

        repo.insert!(x, opts)
      end

    vs_future = Versionstamp.get(tx)

    Future.apply(vs_future, fn vs ->
      Enum.map(result, fn x ->
        pk = Map.get(x, pk_field)

        x =
          if Pack.vs?(pk) do
            pk = Versionstamp.resolve(Map.get(x, pk_field), vs)
            Map.put(x, pk_field, pk)
          else
            x
          end

        FoundationDB.usetenant(x, tenant)
      end)
    end)
  end

  def async_query(_module, repo, fun) do
    # Executes the repo function (e.g. get, get_by, all, etc). Caller must ensure
    # that the proper `:returning` option is used to adhere to the async/await
    # contract.
    _res = fun.()

    case Process.delete(Future.token()) do
      nil ->
        raise "Pipelining failure"

      {{source, schema}, future} ->
        Future.apply(future, fn {return_handler, result} ->
          invoke_return_handler(repo, source, schema, return_handler, result)
        end)
    end
  after
    Process.delete(Future.token())
  end

  defp invoke_return_handler(repo, source, schema, return_handler, result) do
    if is_nil(result), do: raise("Pipelining failure")

    queryable = if is_nil(schema), do: source, else: schema

    # Abuse a :noop option here to signal to the backend that we don't
    # actually want to run a query. Instead, we just want the result to
    # be transformed by Ecto's internal logic.
    case return_handler do
      :all ->
        repo.all(queryable, noop: result)

      :one ->
        repo.one(queryable, noop: result)

      :all_from_source ->
        {select_fields, data_result} = result
        query = from(_ in source, select: ^select_fields)
        repo.all(query, noop: data_result)
    end
  end
end
