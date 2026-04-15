defmodule EctoFoundationDB.Schemas.Session do
  @moduledoc false

  use Ecto.Schema

  alias EctoFoundationDB.Versionstamp

  # The :user_id field is used as a keyspace partition for the primary key.
  # Records with the same user_id are co-located in FDB, enabling efficient
  # range scans like: where: s.id > ^{user_id, checkpoint}
  @schema_context [partition: :user_id]
  @primary_key {:id, Versionstamp, autogenerate: false}

  schema "sessions" do
    field(:user_id, :string)
    field(:data, :string)
  end
end
