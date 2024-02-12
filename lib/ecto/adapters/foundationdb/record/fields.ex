defmodule Ecto.Adapters.FoundationDB.Record.Fields do
  def parse_select_fields(select_fields) do
    select_fields
    |> Enum.map(fn {{:., _, [{:&, [], [0]}, field]}, [], []} -> field end)
  end

  def arrange(fields, field_names) do
    field_names
    |> Enum.map(fn field_name -> {field_name, fields[field_name]} end)
  end

  def strip_field_names_for_ecto(entries) do
    Enum.map(entries, fn fields -> Enum.map(fields, fn {_, v} -> v end) end)
  end

  def get_pk_field!(schema) do
    # TODO: support composite primary key
    [pk_field] = schema.__schema__(:primary_key)
    pk_field
  end

  def to_front(kw = [{first_key, _} | _], key) do
    if first_key == key do
      kw
    else
      val = kw[key]
      [{key, val} | Keyword.delete(kw, key)]
    end
  end
end
