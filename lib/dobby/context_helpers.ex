defmodule Dobby.Context.Helpers do
  @moduledoc """
  Helper functions for Context modules.
  """

  @doc """
  Fetches an option value from a map, supporting both atom and string keys.

  ## Examples

      iex> fetch_opt(%{"key" => "value"}, :key)
      "value"

      iex> fetch_opt(%{key: "value"}, "key")
      "value"

      iex> fetch_opt(%{}, :missing)
      nil
  """
  def fetch_opt(opts, key) when is_map(opts) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
  end

  @doc """
  Fetches an integer option value from a map, supporting both atom and string keys.

  Returns an integer if the value is an integer or can be parsed as one,
  otherwise returns nil.

  ## Examples

      iex> fetch_integer_opt(%{"page" => "42"}, :page)
      42

      iex> fetch_integer_opt(%{page: 42}, "page")
      42

      iex> fetch_integer_opt(%{"page" => "abc"}, :page)
      nil

      iex> fetch_integer_opt(%{}, :page)
      nil
  """
  def fetch_integer_opt(opts, key) when is_map(opts) do
    opts
    |> fetch_opt(key)
    |> to_integer_or_nil()
  end

  defp to_integer_or_nil(nil), do: nil
  defp to_integer_or_nil(value) when is_integer(value), do: value

  defp to_integer_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_integer_or_nil(_), do: nil

  @doc """
  Escapes special characters in a string for use in SQL LIKE queries.
  Escapes `%`, `_`, and backslash characters so they are treated as literals.

  ## Examples

      iex> escape_like("hello%world")
      "hello\\%world"

      iex> escape_like("test_123")
      "test\\_123"

      iex> escape_like("path\\\\to\\\\file")
      "path\\\\\\\\to\\\\\\\\file"
  """
  def escape_like(value) when is_binary(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def escape_like(value), do: value
end
