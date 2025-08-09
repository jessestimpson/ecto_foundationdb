defmodule Crdt.Map.Register do
  def new(crdt, key_or_path, default \\ nil) do
    Crdt.Map.New.new(crdt, key_or_path, :riak_dt_lwwreg, {:assign, default})
  end

  def assign(_, term) do
    {:riak_dt_lwwreg, :update, {:assign, term}}
  end

  def assign(_, term, ts) do
    {:riak_dt_lwwreg, :update, {:assign, term, ts}}
  end

  def remove(_) do
    {:riak_dt_lwwreg, :remove}
  end
end
