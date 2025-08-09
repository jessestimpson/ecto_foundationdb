defmodule Crdt.Map.Counter do
  def new(crdt, key_or_path, default \\ 0) do
    Crdt.Map.New.new(crdt, key_or_path, :riak_dt_emcntr, {:increment, default})
  end

  def increment(_, n \\ 1) do
    {:riak_dt_emcntr, :update, {:increment, n}}
  end

  def decrement(_, n \\ 1) do
    {:riak_dt_emcntr, :update, {:decrement, n}}
  end

  def remove(_) do
    {:riak_dt_emcntr, :remove}
  end
end
