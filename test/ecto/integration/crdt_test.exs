defmodule EctoFoundationDBCrdtTest do
  use ExUnit.Case, async: true

  describe "Counter" do
    test "incr, decr, remove" do
      crdt =
        Crdt.Map.new()
        |> Crdt.Map.for_actor(0)
        |> Crdt.Map.Counter.new("post_1")

      crdt = update_in(crdt, ["post_1"], &Crdt.Map.Counter.increment/1)

      assert 1 = crdt["post_1"]

      crdt = update_in(crdt, ["post_1"], &Crdt.Map.Counter.decrement/1)

      assert 0 = crdt["post_1"]

      crdt = update_in(crdt, ["post_1"], &Crdt.Map.Counter.remove/1)

      assert 0 = map_size(Crdt.Map.value(crdt))
      assert is_nil(crdt["post_1"])
    end

    test "nested: incr, decr, remove" do
      crdt =
        Crdt.Map.new()
        |> Crdt.Map.for_actor(0)
        |> Crdt.Map.Counter.new(["post_1", "comment_1", "reaction_1"])

      assert %{"comment_1" => %{"reaction_1" => 0}} = crdt["post_1"]

      crdt = update_in(crdt, ["post_1", "comment_1", "reaction_1"], &Crdt.Map.Counter.increment/1)

      assert 1 = crdt["post_1"]["comment_1"]["reaction_1"]

      crdt = update_in(crdt["post_1"]["comment_1"]["reaction_1"], &Crdt.Map.Counter.decrement/1)
      assert 0 = crdt["post_1"]["comment_1"]["reaction_1"]
    end
  end

  describe "Flag" do
    test "enable, disable, remove" do
      crdt = Crdt.Map.new() |> Crdt.Map.for_actor(0) |> Crdt.Map.Flag.new(["feature"])
      refute crdt["feature"]

      crdt = update_in(crdt["feature"], &Crdt.Map.Flag.enable/1)
      assert crdt["feature"]

      crdt = update_in(crdt["feature"], &Crdt.Map.Flag.disable/1)
      refute crdt["feature"]

      crdt = update_in(crdt["feature"], &Crdt.Map.Flag.remove/1)
      assert is_nil(crdt["feature"])
    end
  end

  describe "Register" do
    test "assign, remove" do
      crdt = Crdt.Map.new() |> Crdt.Map.for_actor(0) |> Crdt.Map.Register.new(["foo"], "bar")
      assert "bar" = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Register.assign(&1, "baz"))
      assert "baz" = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Register.remove/1)
      assert is_nil(crdt["foo"])
    end
  end

  describe "Set" do
    test "add member, remove member, remove" do
      crdt = Crdt.Map.new() |> Crdt.Map.for_actor(0) |> Crdt.Map.Set.new(["foo"])
      assert [] = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Set.add(&1, "bar"))
      assert ["bar"] = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Set.remove(&1, "bar"))
      assert [] = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Set.remove/1)
      assert is_nil(crdt["foo"])
    end

    test "add all, remove all" do
      crdt = Crdt.Map.new() |> Crdt.Map.for_actor(0) |> Crdt.Map.Set.new(["foo"])
      assert [] = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Set.add_all(&1, ["bar", "baz"]))
      assert ["bar", "baz"] = crdt["foo"]

      crdt = update_in(crdt["foo"], &Crdt.Map.Set.remove_all(&1, ["bar", "baz"]))
      assert [] = crdt["foo"]
    end
  end
end
