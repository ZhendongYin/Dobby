defmodule DobbyWeb.LiveViewHelpersTest do
  use ExUnit.Case, async: true

  alias DobbyWeb.LiveViewHelpers

  describe "parse_integer/2" do
    test "returns default when value is nil" do
      assert LiveViewHelpers.parse_integer(nil, 10) == 10
    end

    test "returns default when value is empty string" do
      assert LiveViewHelpers.parse_integer("", 10) == 10
    end

    test "parses valid integer string" do
      assert LiveViewHelpers.parse_integer("42", 10) == 42
    end

    test "parses negative integer string" do
      assert LiveViewHelpers.parse_integer("-5", 10) == -5
    end

    test "returns default when string is not a valid integer" do
      assert LiveViewHelpers.parse_integer("abc", 10) == 10
    end

    test "parses partial integer from string (Integer.parse behavior)" do
      # Integer.parse("12.5") returns {12, ".5"}, so it parses 12
      assert LiveViewHelpers.parse_integer("12.5", 10) == 12
    end

    test "returns value when already an integer" do
      assert LiveViewHelpers.parse_integer(42, 10) == 42
      assert LiveViewHelpers.parse_integer(-5, 10) == -5
    end

    test "handles whitespace in string" do
      assert LiveViewHelpers.parse_integer("  42  ", 10) == 42
    end

    test "returns default for invalid input types" do
      assert LiveViewHelpers.parse_integer(:atom, 10) == 10
      assert LiveViewHelpers.parse_integer([], 10) == 10
      assert LiveViewHelpers.parse_integer(%{}, 10) == 10
    end
  end
end
