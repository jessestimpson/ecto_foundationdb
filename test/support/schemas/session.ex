defmodule EctoFoundationDB.Schemas.Session do
  @moduledoc false

  use EctoFoundationDB.Schema

  alias EctoFoundationDB.Versionstamp

  @primary_key {:id, Versionstamp, autogenerate: false, partition: :user_id}

  schema "sessions" do
    field(:user_id, :string)
    field(:data, :string)
  end
end
