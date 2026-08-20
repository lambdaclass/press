defmodule Press.Font.MetricsTest do
  use ExUnit.Case, async: true

  alias Press.Font.Metrics

  describe "font_for/3" do
    test "selects the correct PDF base font atom for Helvetica variants" do
      assert Metrics.font_for(:helvetica, :normal, :normal) == :helvetica
      assert Metrics.font_for(:helvetica, :bold, :normal) == :helvetica_bold
      assert Metrics.font_for(:helvetica, :normal, :italic) == :helvetica_oblique
      assert Metrics.font_for(:helvetica, :bold, :italic) == :helvetica_bold_oblique
    end

    test "selects the correct PDF base font atom for Times variants" do
      assert Metrics.font_for(:times, :normal, :normal) == :times_roman
      assert Metrics.font_for(:times, :bold, :normal) == :times_bold
      assert Metrics.font_for(:times, :normal, :italic) == :times_italic
      assert Metrics.font_for(:times, :bold, :italic) == :times_bold_italic
    end

    test "selects the correct PDF base font atom for Courier variants" do
      assert Metrics.font_for(:courier, :normal, :normal) == :courier
      assert Metrics.font_for(:courier, :bold, :normal) == :courier_bold
      assert Metrics.font_for(:courier, :normal, :italic) == :courier_oblique
      assert Metrics.font_for(:courier, :bold, :italic) == :courier_bold_oblique
    end

    test "falls back to helvetica for unknown families" do
      assert Metrics.font_for(:sans_serif, :normal, :normal) == :helvetica
      assert Metrics.font_for(:arial, :bold, :normal) == :helvetica_bold
    end
  end

  describe "char_width/2" do
    test "Courier is fixed-width (600 units) for all characters" do
      assert Metrics.char_width(:courier, ?A) == 600
      assert Metrics.char_width(:courier, ?i) == 600
      assert Metrics.char_width(:courier, ?\s) == 600
    end

    test "Helvetica has proportional widths" do
      assert Metrics.char_width(:helvetica, ?i) < Metrics.char_width(:helvetica, ?W)
      assert Metrics.char_width(:helvetica, ?\s) == 278
    end

    test "Times has proportional widths" do
      assert Metrics.char_width(:times_roman, ?i) < Metrics.char_width(:times_roman, ?M)
      assert Metrics.char_width(:times_roman, ?\s) == 250
    end

    test "Helvetica bold and fallback font widths" do
      assert Metrics.char_width(:helvetica_bold, ?A) > 0
      assert Metrics.char_width(:unknown_font, ?A) == Metrics.char_width(:helvetica, ?A)
    end
  end

  describe "text_width/3" do
    test "computes total text width in points given font size" do
      # Courier: 5 characters * 600 / 1000 * 10pt = 30pt
      assert_in_delta Metrics.text_width(:courier, "Hello", 10.0), 30.0, 0.01

      # Empty string has 0 width
      assert Metrics.text_width(:helvetica, "", 12.0) == 0.0

      # Proportional width scales linearly with font size
      w12 = Metrics.text_width(:helvetica, "Invoice #123", 12.0)
      w24 = Metrics.text_width(:helvetica, "Invoice #123", 24.0)
      assert_in_delta w24, w12 * 2.0, 0.01
    end
  end
end
