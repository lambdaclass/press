defmodule Press.PDF.SyntaxTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Syntax

  describe "number/1" do
    test "renders integers without a decimal point" do
      assert Syntax.number(12) == "12"
      assert Syntax.number(0) == "0"
    end

    test "renders whole-number floats without a decimal point" do
      assert Syntax.number(12.0) == "12"
    end

    test "renders fractional floats trimmed of trailing zeros" do
      assert Syntax.number(12.5) == "12.5"
      assert Syntax.number(0.25) == "0.25"
    end
  end

  describe "escape_string/1" do
    test "escapes backslashes and parentheses" do
      assert Syntax.escape_string("a(b)c\\d") == "a\\(b\\)c\\\\d"
    end

    test "leaves plain text untouched" do
      assert Syntax.escape_string("Hello world!") == "Hello world!"
    end
  end
end
