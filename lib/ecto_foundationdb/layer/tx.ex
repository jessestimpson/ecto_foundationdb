defmodule EctoFoundationDB.Layer.Tx do
  @moduledoc false
  alias EctoFoundationDB.Exception.IncorrectTenancy
  alias EctoFoundationDB.Exception.Unsupported
  alias EctoFoundationDB.Future
  alias EctoFoundationDB.Indexer
  alias EctoFoundationDB.Layer.DecodedKV
  alias EctoFoundationDB.Layer.Fields
  alias EctoFoundationDB.Layer.Pack
  alias EctoFoundationDB.Layer.PrimaryKVCodec
  alias EctoFoundationDB.Layer.TxInsert
  alias EctoFoundationDB.Schema
  alias EctoFoundationDB.Tenant

  @tenant :__ectofdbtxcontext__
  @tx :__ectofdbtx__

  def in_tenant_tx?() do
    tenant = Process.get(@tenant)
    flag = in_tx?() and tenant.__struct__ == Tenant
    {flag, tenant}
  end

  def in_tx?(), do: not is_nil(Process.get(@tx))

  def safe?(nil) do
    case in_tenant_tx?() do
      {true, tenant} ->
        {true, tenant}

      {false, _} ->
        {false, :missing_tenant}
    end
  end

  def safe?(tenant) do
    if tenant.__struct__ == Tenant do
      {true, tenant}
    else
      {false, :missing_tenant}
    end
  end

  def transactional_external(tenant, fun) do
    nil = Process.get(@tenant)
    nil = Process.get(@tx)

    :erlfdb.transactional(
      Tenant.txobj(tenant),
      fn tx ->
        Process.put(@tenant, tenant)
        Process.put(@tx, tx)

        try do
          cond do
            is_function(fun, 0) -> fun.()
            is_function(fun, 1) -> fun.(tx)
          end
        after
          Process.delete(@tx)
          Process.delete(@tenant)
        end
      end
    )
  end

  def transactional(nil, fun) do
    case Process.get(@tx, nil) do
      nil ->
        raise IncorrectTenancy, """
        FoundationDB Adapter has no transactional context to execute on.
        """

      tx ->
        fun.(tx)
    end
  end

  def transactional(context, fun) do
    case Process.get(@tenant, nil) do
      nil ->
        try do
          Process.put(@tenant, context)

          :erlfdb.transactional(Tenant.txobj(context), fn tx ->
            Process.put(@tx, tx)
            fun.(tx)
          end)
        after
          Process.delete(@tx)
          Process.delete(@tenant)
        end

      ^context ->
        tx = Process.get(@tx, nil)
        fun.(tx)

      orig ->
        raise IncorrectTenancy, """
        FoundationDB Adapter encountered a transaction where the original transaction context \
        #{inspect(orig)} did not match the prefix on a struct or query within the transaction: \
        #{inspect(context)}.

        This can be encountered when a struct read from one tenant is provided to a transaction from \
        another. In these cases, the prefix must explicitly be removed from the struct metadata.
        """
    end
  end

  def insert_all(tenant, tx, {schema, source, context}, entries, {idxs, partial_idxs}, options) do
    write_primary = Schema.get_option(context, :write_primary)

    tx_insert = TxInsert.new(tenant, schema, idxs, partial_idxs, write_primary, options)

    case options[:conflict_target] do
      [] ->
        # We pretend that the data doesn't exist. This speeds up data loading
        # but can result in inconsistent indexes if objects do exist in
        # the database that are being blindly overwritten.

        Enum.each(entries, fn {{pk_field, pk}, _future, data_object} ->
          kv_codec = Pack.primary_codec(tenant, source, pk)
          data_object = Fields.to_front(data_object, pk_field)
          kv = %DecodedKV{codec: kv_codec, data_object: data_object}
          TxInsert.do_set(tx_insert, tx, kv, nil)
        end)

        length(entries)

      nil ->
        entries
        |> Enum.map(fn {{pk_field, pk}, future, data_object} ->
          data_object = Fields.to_front(data_object, pk_field)

          kv_codec = Pack.primary_codec(tenant, source, pk)

          kv_codec
          |> then(&async_get(tenant, tx, &1, future))
          |> Future.apply(
            &TxInsert.do_set(
              tx_insert,
              tx,
              %DecodedKV{codec: kv_codec, data_object: data_object},
              &1
            )
          )
        end)
        |> Future.await_stream()
        |> Stream.map(&Future.result/1)
        |> Enum.reduce(0, fn
          nil, sum -> sum
          :ok, sum -> sum + 1
        end)

      unsupported_conflict_target ->
        raise Unsupported, """
        The :conflict_target option provided is not supported by the FoundationDB Adapter.

        You provided #{inspect(unsupported_conflict_target)}.

        Instead, we suggest you do not use this option at all.

        FoundationDB Adapter does support `conflict_target: []`, but this using this option
        can result in inconsistent indexes, and it is only recommended if you know ahead of
        time that your data does not already exist in the database.
        """
    end
  end

  def update_pks(
        tenant,
        tx,
        {schema, source, context},
        pk_field,
        pk_futures,
        set_data,
        {idxs, partial_idxs},
        options
      ) do
    write_primary = Schema.get_option(context, :write_primary)

    futures =
      Enum.map(pk_futures, fn {pk, future} ->
        kv_codec = Pack.primary_codec(tenant, source, pk)
        future = async_get(tenant, tx, kv_codec, future)

        Future.apply(future, fn
          nil ->
            nil

          decoded_kv ->
            update_data_object(
              tenant,
              tx,
              schema,
              pk_field,
              {decoded_kv, [set: set_data]},
              {idxs, partial_idxs},
              write_primary,
              options
            )

            :ok
        end)
      end)

    futures
    |> Future.await_stream()
    |> Stream.map(&Future.result/1)
    |> Enum.reduce(0, fn
      nil, sum -> sum
      :ok, sum -> sum + 1
    end)
  end

  def update_data_object(
        tenant,
        tx,
        schema,
        pk_field,
        {decoded_kv, updates},
        {idxs, partial_idxs},
        write_primary,
        options
      ) do
    %DecodedKV{codec: kv_codec, data_object: orig_data_object} = decoded_kv
    orig_data_object = Fields.to_front(orig_data_object, pk_field)
    data_object = Keyword.merge(orig_data_object, updates[:set])

    {_, kvs} = PrimaryKVCodec.encode(kv_codec, Pack.to_fdb_value(data_object), options)

    # For multikey object, metadata is in the key, so the key will always change and must be cleared.
    {fdb_key, clear_end} = PrimaryKVCodec.range(kv_codec)

    if write_primary do
      # If the original object was not multikey, there's no need to do the clear_range
      if decoded_kv.multikey?, do: :erlfdb.clear_range(tx, fdb_key <> <<0>>, clear_end)
      for {k, v} <- kvs, do: :erlfdb.set(tx, k, v)
    else
      :erlfdb.clear_range(tx, fdb_key, clear_end)
    end

    Indexer.update(tenant, tx, idxs, partial_idxs, schema, {fdb_key, orig_data_object}, updates)
  end

  def delete_pks(tenant, tx, {schema, source, _context}, pk_futures, {idxs, partial_idxs}) do
    futures =
      Enum.map(pk_futures, fn {pk, future} ->
        kv_codec = Pack.primary_codec(tenant, source, pk)
        future = async_get(tenant, tx, kv_codec, future)

        Future.apply(future, fn
          nil ->
            nil

          decoded_kv ->
            delete_data_object(
              tenant,
              tx,
              schema,
              decoded_kv,
              {idxs, partial_idxs}
            )

            :ok
        end)
      end)

    futures
    |> Future.await_stream()
    |> Stream.map(&Future.result/1)
    |> Enum.reduce(0, fn
      nil, sum -> sum
      :ok, sum -> sum + 1
    end)
  end

  def delete_data_object(
        tenant,
        tx,
        schema,
        decoded_kv,
        {idxs, partial_idxs}
      ) do
    %DecodedKV{codec: kv_codec, data_object: v} = decoded_kv

    {start_key, end_key} = PrimaryKVCodec.range(kv_codec)

    if decoded_kv.multikey? do
      :erlfdb.clear_range(tx, start_key, end_key)
    else
      :erlfdb.clear(tx, start_key)
    end

    Indexer.clear(tenant, tx, idxs, partial_idxs, schema, {start_key, v})
  end

  def clear_all(tenant, tx, %{opts: _adapter_opts}, source) do
    # this key prefix will clear datakeys and indexkeys, but not user data or migration data
    {key_start, key_end} = Pack.adapter_source_range(tenant, source)

    # this would be a lot faster if we didn't have to count the keys
    num = count_range(tx, key_start, key_end)
    :erlfdb.clear_range(tx, key_start, key_end)
    num
  end

  def watch(tenant, tx, {_schema, source, context}, {_pk_field, pk}, _options) do
    if not Schema.get_option(context, :write_primary) do
      raise Unsupported, "Watches on schemas with `write_primary: false` are not supported."
    end

    kv_codec = Pack.primary_codec(tenant, source, pk)
    key = PrimaryKVCodec.pack_key(kv_codec, nil)

    fut = :erlfdb.watch(tx, key)
    fut
  end

  defp count_range(tx, key_start, key_end) do
    :erlfdb.fold_range(tx, key_start, key_end, fn _kv, acc -> acc + 1 end, 0)
  end

  defp async_get(tenant, tx, kv_codec, future) do
    {start_key, end_key} = PrimaryKVCodec.range(kv_codec)
    future_ref = :erlfdb.get_range(tx, start_key, end_key, wait: false)

    f = fn
      [] ->
        nil

      [{k, v}] ->
        %DecodedKV{
          codec: Pack.primary_write_key_to_codec(tenant, k),
          data_object: Pack.from_fdb_value(v)
        }

      kvs ->
        [kv] =
          kvs
          |> PrimaryKVCodec.stream_decode(tenant)
          |> Enum.to_list()

        kv
    end

    Future.set(future, tx, future_ref, f)
  end
end
