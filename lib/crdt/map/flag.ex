defmodule Crdt.Map.Flag do
  def new(crdt, key_or_path, default \\ :disable) do
    Crdt.Map.New.new(crdt, key_or_path, :riak_dt_od_flag, default)
  end

  def enable(_) do
    {:riak_dt_od_flag, :update, :enable}
  end

  def disable(_) do
    {:riak_dt_od_flag, :update, :disable}
  end

  def remove(_) do
    {:riak_dt_od_flag, :remove}
  end
end
