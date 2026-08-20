defmodule Press.CSS.ValueTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Value

  describe "parse_color/1" do
    test "parses 6-digit and 3-digit hex" do
      assert Value.parse_color("#ff0000") == {:ok, {1.0, 0.0, 0.0}}
      assert Value.parse_color("#F00") == {:ok, {1.0, 0.0, 0.0}}
    end

    test "parses rgb()" do
      assert Value.parse_color("rgb(255, 0, 0)") == {:ok, {1.0, 0.0, 0.0}}
    end

    test "parses named colors case-insensitively" do
      assert Value.parse_color("Red") == {:ok, {1.0, 0.0, 0.0}}
      assert Value.parse_color("black") == {:ok, {0.0, 0.0, 0.0}}
    end

    test "parses oklch()" do
      {:ok, {r, g, b}} = Value.parse_color("oklch(96% 0.001 286.375)")
      assert r > 0.9 and g > 0.9 and b > 0.9
    end

    test "parses CSS variables for daisyUI themes" do
      assert Value.parse_color("var(--color-base-100)") == {:ok, {0.98, 0.98, 0.98}}
      {:ok, {r, g, b}} = Value.parse_color("var(--color-base-200)")
      assert r > 0.9 and g > 0.9 and b > 0.9
    end

    test "rejects unrecognized color text" do
      assert Value.parse_color("notacolor") == :error
    end
  end

  describe "parse_length/1" do
    test "parses a number with a unit" do
      assert Value.parse_length("12px") == {:ok, {:length, 12.0, :px}}
      assert Value.parse_length("1.5em") == {:ok, {:length, 1.5, :em}}
      assert Value.parse_length("50%") == {:ok, {:length, 50.0, :percent}}
    end

    test "accepts unitless 0" do
      assert Value.parse_length("0") == {:ok, {:length, 0, :pt}}
    end

    test "rejects an unrecognized unit" do
      assert Value.parse_length("12furlongs") == :error
    end

    test "rejects a nonzero unitless number" do
      assert Value.parse_length("12") == :error
    end
  end

  describe "parse_line_height/1" do
    test "parses a bare unitless number as a multiplier" do
      assert Value.parse_line_height("1.5") == {:ok, {:line_height, :multiplier, 1.5}}
    end

    test "parses an explicit length" do
      assert Value.parse_line_height("14pt") == {:ok, {:length, 14.0, :pt}}
    end

    test "rejects percent" do
      assert Value.parse_line_height("150%") == :error
    end
  end

  describe "parse_keyword/2" do
    test "matches a valid keyword" do
      assert Value.parse_keyword("bold", [:normal, :bold]) == {:ok, :bold}
    end

    test "is case-insensitive" do
      assert Value.parse_keyword("BOLD", [:normal, :bold]) == {:ok, :bold}
    end

    test "rejects a keyword not in the valid set" do
      assert Value.parse_keyword("italic", [:normal, :bold]) == :error
    end
  end
end
