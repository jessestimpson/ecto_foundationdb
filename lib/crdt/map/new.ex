defmodule Crdt.Map.New do
  def new(crdt = %Crdt.Map{actor: actor}, path, type, init_op)
      when is_list(path) and not is_nil(actor) do
    %{dt: dt} = crdt
    map_op = Crdt.Map.make_map_op(path, type, init_op)
    {:ok, dt} = :riak_dt_map.update(map_op, actor, dt)
    %{crdt | dt: dt}
  end

  def new(crdt = %Crdt.Map{}, key, type, init_op) do
    new(crdt, [key], type, init_op)
  end
end
