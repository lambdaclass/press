defmodule Press.PDF.FontsTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Fonts

  test "maps every standard font atom to its PDF BaseFont name" do
    assert Fonts.base_font_name(:helvetica) == "Helvetica"
    assert Fonts.base_font_name(:helvetica_bold) == "Helvetica-Bold"
    assert Fonts.base_font_name(:helvetica_oblique) == "Helvetica-Oblique"
    assert Fonts.base_font_name(:helvetica_bold_oblique) == "Helvetica-BoldOblique"
    assert Fonts.base_font_name(:times_roman) == "Times-Roman"
    assert Fonts.base_font_name(:times_bold) == "Times-Bold"
    assert Fonts.base_font_name(:times_italic) == "Times-Italic"
    assert Fonts.base_font_name(:times_bold_italic) == "Times-BoldItalic"
    assert Fonts.base_font_name(:courier) == "Courier"
    assert Fonts.base_font_name(:courier_bold) == "Courier-Bold"
    assert Fonts.base_font_name(:courier_oblique) == "Courier-Oblique"
    assert Fonts.base_font_name(:courier_bold_oblique) == "Courier-BoldOblique"
    assert Fonts.base_font_name(:symbol) == "Symbol"
    assert Fonts.base_font_name(:zapf_dingbats) == "ZapfDingbats"
  end

  test "standard_fonts/0 lists all 14 atoms" do
    assert length(Fonts.standard_fonts()) == 14
    assert :helvetica in Fonts.standard_fonts()
  end
end
