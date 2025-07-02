defmodule EctoFoundationDB.Schemas.QueueItem do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}

  schema "queue" do
    field(:data, :binary)
  end
end
