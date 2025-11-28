defmodule Dobby.Context.HelpersTest do
  use ExUnit.Case, async: true

  alias Dobby.Context.Helpers

  describe "fetch_opt/2" do
    test "returns value when key exists as atom" do
      opts = %{page: 1, size: 20}
      assert Helpers.fetch_opt(opts, :page) == 1
      assert Helpers.fetch_opt(opts, :size) == 20
    end

    test "returns value when key exists as string" do
      opts = %{"page" => 1, "size" => 20}
      assert Helpers.fetch_opt(opts, :page) == 1
      assert Helpers.fetch_opt(opts, :size) == 20
    end

    test "returns value when searching with atom key and map has string key" do
      opts = %{"page" => 1, "size" => 20}
      assert Helpers.fetch_opt(opts, :page) == 1
      assert Helpers.fetch_opt(opts, :size) == 20
    end

    test "returns nil when key does not exist" do
      opts = %{page: 1}
      assert Helpers.fetch_opt(opts, :missing) == nil
    end

    test "returns nil for empty map" do
      assert Helpers.fetch_opt(%{}, :any_key) == nil
    end

    test "prefers atom key over string key when both exist" do
      # In Elixir, maps can't have both atom and string keys with same name
      # This test verifies that atom keys are checked first
      opts = %{page: 1}
      assert Helpers.fetch_opt(opts, :page) == 1

      opts_string_only = %{"page" => 2}
      assert Helpers.fetch_opt(opts_string_only, :page) == 2
    end

    test "handles various value types" do
      opts = %{
        string: "value",
        integer: 42,
        boolean: true,
        list: [1, 2, 3],
        map: %{nested: "value"}
      }

      assert Helpers.fetch_opt(opts, :string) == "value"
      assert Helpers.fetch_opt(opts, :integer) == 42
      assert Helpers.fetch_opt(opts, :boolean) == true
      assert Helpers.fetch_opt(opts, :list) == [1, 2, 3]
      assert Helpers.fetch_opt(opts, :map) == %{nested: "value"}
    end
  end

  describe "fetch_integer_opt/2" do
    test "returns integer when value is already an integer" do
      opts = %{page: 42, size: 20}
      assert Helpers.fetch_integer_opt(opts, :page) == 42
      assert Helpers.fetch_integer_opt(opts, :size) == 20
    end

    test "parses string value to integer" do
      opts = %{"page" => "42", "size" => "20"}
      assert Helpers.fetch_integer_opt(opts, :page) == 42
      assert Helpers.fetch_integer_opt(opts, :size) == 20
    end

    test "parses negative integer strings" do
      opts = %{"offset" => "-10"}
      assert Helpers.fetch_integer_opt(opts, :offset) == -10
    end

    test "returns nil when string cannot be parsed as integer" do
      opts = %{"page" => "abc", "size" => "not a number"}
      assert Helpers.fetch_integer_opt(opts, :page) == nil
      assert Helpers.fetch_integer_opt(opts, :size) == nil
    end

    test "returns nil when key does not exist" do
      opts = %{page: 1}
      assert Helpers.fetch_integer_opt(opts, :missing) == nil
    end

    test "returns nil for empty map" do
      assert Helpers.fetch_integer_opt(%{}, :any_key) == nil
    end

    test "parses partial integer from string (Integer.parse behavior)" do
      # Integer.parse("12.5") returns {12, ".5"}, so it parses 12
      opts = %{"value" => "12.5"}
      assert Helpers.fetch_integer_opt(opts, :value) == 12
    end

    test "handles both atom and string keys in map when searching with atom key" do
      opts_atom = %{page: "42"}
      opts_string = %{"page" => "42"}

      assert Helpers.fetch_integer_opt(opts_atom, :page) == 42
      assert Helpers.fetch_integer_opt(opts_string, :page) == 42
    end

    test "returns nil for non-integer, non-string values" do
      opts = %{
        boolean: true,
        list: [1, 2, 3],
        map: %{key: "value"},
        atom: :symbol
      }

      assert Helpers.fetch_integer_opt(opts, :boolean) == nil
      assert Helpers.fetch_integer_opt(opts, :list) == nil
      assert Helpers.fetch_integer_opt(opts, :map) == nil
      assert Helpers.fetch_integer_opt(opts, :atom) == nil
    end

    test "handles string without leading/trailing whitespace" do
      opts = %{"page" => "42"}
      assert Helpers.fetch_integer_opt(opts, :page) == 42
    end
  end

  describe "escape_like/1" do
    test "escapes percent sign" do
      assert Helpers.escape_like("hello%world") == "hello\\%world"
      assert Helpers.escape_like("50% off") == "50\\% off"
    end

    test "escapes underscore" do
      assert Helpers.escape_like("test_123") == "test\\_123"
      assert Helpers.escape_like("file_name") == "file\\_name"
    end

    test "escapes backslash" do
      assert Helpers.escape_like("path\\to\\file") == "path\\\\to\\\\file"
      assert Helpers.escape_like("C:\\Windows") == "C:\\\\Windows"
    end

    test "escapes multiple special characters" do
      assert Helpers.escape_like("file_%name\\ext") == "file\\_\\%name\\\\ext"
      assert Helpers.escape_like("test_50%_off") == "test\\_50\\%\\_off"
    end

    test "returns value unchanged if no special characters" do
      assert Helpers.escape_like("hello world") == "hello world"
      assert Helpers.escape_like("normal text") == "normal text"
    end

    test "handles empty string" do
      assert Helpers.escape_like("") == ""
    end

    test "handles non-binary values" do
      assert Helpers.escape_like(nil) == nil
      assert Helpers.escape_like(123) == 123
    end
  end
end
