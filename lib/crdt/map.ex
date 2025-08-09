defmodule Crdt.Map do
  @behaviour Access
  defstruct [:dt, :actor]

  def new() do
    %__MODULE__{dt: :riak_dt_map.new()}
  end

  def for_actor(crdt = %__MODULE__{}, actor) do
    %{crdt | actor: actor}
  end

  def value(crdt = %__MODULE__{}) do
    %{dt: dt} = crdt

    dt
    |> :riak_dt_map.value(dt)
    |> Crdt.Map.Access.new()
    |> Crdt.Map.Access.value()
  end

  @impl Access
  def fetch(crdt = %__MODULE__{}, key) do
    %{dt: dt} = crdt

    dt
    |> :riak_dt_map.value(dt)
    |> Crdt.Map.Access.new()
    |> Crdt.Map.Access.fetch(key)
  end

  @impl Access
  def get_and_update(crdt = %__MODULE__{actor: actor}, key, function) when not is_nil(actor) do
    {current_val, new_val} = function.(Crdt.Map.Access.new([]))

    map_op =
      case new_val do
        access = %Crdt.Map.Access{} ->
          field_name = {key, :riak_dt_map}
          field_op = {:update, field_name, Crdt.Map.Access.make_map_op(access)}
          map_op = {:update, [field_op]}
          map_op

        {type, :update, crdt_op} ->
          field_name = {key, type}
          field_op = {:update, field_name, crdt_op}
          map_op = {:update, [field_op]}
          map_op

        {type, :remove} ->
          field_name = {key, type}
          field_op = {:remove, field_name}
          map_op = {:update, [field_op]}
          map_op
      end

    %{dt: dt} = crdt
    {:ok, dt} = :riak_dt_map.update(map_op, actor, dt)
    {current_val, %{crdt | dt: dt}}
  end

  @impl Access
  def pop(_crdt, _key) do
    raise "Must use update"
  end

  def make_map_op([key], type, crdt_op) do
    field_name = {key, type}
    map_field_update = {:update, field_name, crdt_op}
    map_op = {:update, [map_field_update]}
    map_op
  end

  def make_map_op([h | t], type, crdt_op) do
    field_name = {h, :riak_dt_map}
    map_field_update = {:update, field_name, make_map_op(t, type, crdt_op)}
    map_op = {:update, [map_field_update]}
    map_op
  end
end
