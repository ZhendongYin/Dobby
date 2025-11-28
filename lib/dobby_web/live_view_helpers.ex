defmodule DobbyWeb.LiveViewHelpers do
  @moduledoc """
  Helper functions for LiveView modules.
  """

  @doc """
  Parses an integer value from various input types.

  Returns the parsed integer if valid, otherwise returns the default value.

  ## Examples

      iex> parse_integer("42", 10)
      42

      iex> parse_integer(nil, 10)
      10

      iex> parse_integer("abc", 10)
      10

      iex> parse_integer(42, 10)
      42
  """
  def parse_integer(nil, default), do: default

  def parse_integer("", default), do: default

  def parse_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, _} -> int
      :error -> default
    end
  end

  def parse_integer(value, _default) when is_integer(value), do: value

  def parse_integer(_, default), do: default
end
