defmodule Press.Font.WidthsTest do
  use ExUnit.Case, async: true

  alias Press.Font.Widths

  describe "char_width/2" do
    test "matches the published AFM advance widths" do
      assert Widths.char_width(:helvetica, ?\s) == 278
      assert Widths.char_width(:helvetica, ?A) == 667
      assert Widths.char_width(:helvetica_bold, ?A) == 722
      assert Widths.char_width(:times_roman, ?\s) == 250
      assert Widths.char_width(:times_roman, ?A) == 722
    end

    test "each Times variant has its own table" do
      # Times-Bold is wider than Times-Roman at 'n'; sharing one table for all
      # four variants is what made bold serif text drift.
      assert Widths.char_width(:times_bold, ?n) != Widths.char_width(:times_roman, ?n)
      assert Widths.char_width(:times_italic, ?a) != Widths.char_width(:times_roman, ?a)
    end

    test "courier is monospaced" do
      for cp <- [?\s, ?i, ?W, ?ñ] do
        assert Widths.char_width(:courier, cp) == 600
      end
    end

    test "covers the Latin-1 range the Spanish templates need" do
      for cp <- [?á, ?é, ?í, ?ó, ?ú, ?ñ, ?Ñ, ?Á, ?¿, ?¡, ?°, ?º] do
        assert Widths.char_width(:helvetica, cp) > 0
      end

      # An accented letter must not fall back to the generic width.
      assert Widths.char_width(:helvetica, ?í) == 278
      assert Widths.char_width(:helvetica, ?ñ) == 556
    end

    test "covers the WinAnsi punctuation above Latin-1" do
      assert Widths.char_width(:helvetica, 0x2014) == 1000
      assert Widths.char_width(:helvetica, 0x20AC) == 556
    end

    test "an unknown font falls back to helvetica" do
      assert Widths.char_width(:not_a_font, ?A) == Widths.char_width(:helvetica, ?A)
    end
  end

  describe "ascent_descent/1" do
    test "returns the published vertical metrics" do
      assert Widths.ascent_descent(:helvetica) == {718, -207}
      assert Widths.ascent_descent(:times_roman) == {683, -217}
    end
  end
end
