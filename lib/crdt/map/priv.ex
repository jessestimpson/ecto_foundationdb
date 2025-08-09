defmodule Crdt.Map.Priv do
  def field_value!(:riak_dt_emcntr, val), do: val

  def field_value!(:riak_dt_od_flag, boolean), do: boolean

  def field_value!(:riak_dt_lwwreg, value), do: value

  def field_value!(:riak_dt_orswot, list), do: list

  def field_value!(:riak_dt_map, val) do
    for {{key, type}, value} <- val, do: {key, field_value!(type, value)}, into: %{}
  end
end
