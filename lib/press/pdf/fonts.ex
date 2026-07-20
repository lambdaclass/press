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

  def base_font_name(atom), do: Map.fetch!(@base_fonts, atom)

  def standard_fonts, do: Map.keys(@base_fonts)
end
