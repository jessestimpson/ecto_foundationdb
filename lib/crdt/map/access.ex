defmodule Crdt.Map.Access do
  @behaviour Access

  defstruct [:map]

  def new(val) do
    map = for {{key, type}, v} <- val, do: {key, {type, v}}, into: %{}
    %__MODULE__{map: map}
  end

  def value(access = %__MODULE__{}) do
    %{map: map} = access

    for {key, {type, val}} <- map, do: {key, Crdt.Map.Priv.field_value!(type, val)}, into: %{}
  end

  @impl Access
  def fetch(access = %__MODULE__{}, key) do
    %{map: map} = access

    case Map.fetch(map, key) do
      {:ok, {type, val}} ->
        {:ok, Crdt.Map.Priv.field_value!(type, val)}

      :error ->
        :error
    end
  end

  @impl Access
  def get_and_update(access = %__MODULE__{}, key, function) do
    {current_val, new_val} = function.(new([]))
    %{map: map} = access
    map = Map.put(map, key, new_val)
    {current_val, %{access | map: map}}
  end

  @impl Access
  def pop(_access, _key) do
    raise "Must use update"
  end

  def fetch_typed(access = %__MODULE__{}, key) do
    %{map: map} = access
    Map.fetch(map, key)
  end

  def make_map_op(access = %__MODULE__{}) do
    %{map: map} = access

    map_field_updates =
      Enum.map(
        map,
        fn
          {k, v = %__MODULE__{}} ->
            field_name = {k, :riak_dt_map}
            map_field_update = {:update, field_name, make_map_op(v)}
            map_field_update

          {k, {type, :update, crdt_op}} ->
            field_name = {k, type}
            map_field_update = {:update, field_name, crdt_op}
            map_field_update

          {k, {type, :remove}} ->
            field_name = {k, type}
            map_field_op = {:remove, field_name}
            map_field_op
        end
      )

    map_op = {:update, map_field_updates}
    map_op
  end
end
