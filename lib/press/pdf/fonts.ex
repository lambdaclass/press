defmodule Press.PDF.Fonts do
  @moduledoc false

  @base_fonts %{
    helvetica: "Helvetica",
    helvetica_bold: "Helvetica-Bold",
    helvetica_oblique: "Helvetica-Oblique",
    helvetica_bold_oblique: "Helvetica-BoldOblique",
    times_roman: "Times-Roman",
    times_bold: "Times-Bold",
    times_italic: "Times-Italic",
    times_bold_italic: "Times-BoldItalic",
    courier: "Courier",
    courier_bold: "Courier-Bold",
    courier_oblique: "Courier-Oblique",
    courier_bold_oblique: "Courier-BoldOblique",
    symbol: "Symbol",
    zapf_dingbats: "ZapfDingbats"
  }

  # WinAnsi is Latin-1 except for 0x80..0x9F, where Windows put typographic
  # punctuation instead of control characters.
  @winansi_high %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  def base_font_name(atom), do: Map.fetch!(@base_fonts, atom)

  @doc """
  Advance widths for character codes 32..255, in the order a PDF `/Widths`
  array expects.

  These come from the AFM metrics the layout already measured with, not from
  the embedded font file: `/Widths` is what the reader positions text by, so
  taking them from the same source keeps the drawn page identical to the one
  that was laid out.
  """
  def winansi_widths(font) do
    Enum.map(32..255, fn code ->
      Press.Font.Widths.char_width(font, Map.get(@winansi_high, code, code))
    end)
  end

  def standard_fonts, do: Map.keys(@base_fonts)
end
