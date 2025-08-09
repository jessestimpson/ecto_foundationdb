defmodule Crdt.Map.Set do
  def new(crdt, key_or_path, default \\ []) do
    Crdt.Map.New.new(crdt, key_or_path, :riak_dt_orswot, {:add_all, default})
  end

  def add(_, member) do
    {:riak_dt_orswot, :update, {:add, member}}
  end

  def add_all(_, members) do
    {:riak_dt_orswot, :update, {:add_all, members}}
  end

  def remove(_, member) do
    {:riak_dt_orswot, :update, {:remove, member}}
  end

  def remove_all(_, members) do
    {:riak_dt_orswot, :update, {:remove_all, members}}
  end

  def remove(_) do
    {:riak_dt_orswot, :remove}
  end
end
