defmodule EctoFoundationDB.Exception.TransactionsDisabled do
  @moduledoc """
  This exception is raised when your application has decided to disable
  all transactions. It is never raised unless your application has requested
  it.
  """
  defexception [:message]
end
