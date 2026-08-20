defmodule Press.PDF.ContentStream do
  @moduledoc false

  alias Press.PDF.Syntax

  def render(ops, font_resource_names, image_resource_names \\ %{}) do
    Enum.map_join(ops, "\n", &render_op(&1, font_resource_names, image_resource_names))
  end

  defp render_op(
         {:text, x, y, font, size, {r, g, b}, text},
         font_resource_names,
         _image_resource_names
       ) do
    resource = Map.fetch!(font_resource_names, font)

    Enum.join(
      [
        "q",
        "#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} rg",
        "BT",
        "#{resource} #{Syntax.number(size)} Tf",
        "#{Syntax.number(x)} #{Syntax.number(y)} Td",
        "(#{text |> to_winansi() |> Syntax.escape_string()}) Tj",
        "ET",
        "Q"
      ],
      "\n"
    )
  end

  defp render_op(
         {:rect, x, y, w, h, fill, stroke, stroke_width},
         _font_resource_names,
         _image_resource_names
       ) do
    ["q"]
    |> add_fill_color(fill)
    |> add_stroke_color(stroke, stroke_width)
    |> Kernel.++([
      "#{Syntax.number(x)} #{Syntax.number(y)} #{Syntax.number(w)} #{Syntax.number(h)} re",
      paint_operator(fill, stroke),
      "Q"
    ])
    |> Enum.join("\n")
  end

  defp render_op({:image, x, y, w, h, %{id: id}}, _font_resource_names, image_resource_names) do
    resource = Map.fetch!(image_resource_names, id)

    Enum.join(
      [
        "q",
        "#{Syntax.number(w)} 0 0 #{Syntax.number(h)} #{Syntax.number(x)} #{Syntax.number(y)} cm",
        "#{resource} Do",
        "Q"
      ],
      "\n"
    )
  end

  defp add_fill_color(lines, nil), do: lines

  defp add_fill_color(lines, {r, g, b}) do
    lines ++ ["#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} rg"]
  end

  defp add_stroke_color(lines, nil, _width), do: lines

  defp add_stroke_color(lines, {r, g, b}, width) do
    lines ++
      [
        "#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} RG",
        "#{Syntax.number(width)} w"
      ]
  end

  defp paint_operator(nil, nil), do: "n"
  defp paint_operator(_fill, nil), do: "f"
  defp paint_operator(nil, _stroke), do: "S"
  defp paint_operator(_fill, _stroke), do: "B"

  # WinAnsiEncoding maps Windows-1252 (ISO-8859-1 for 0x00-0x7F and 0xA0-0xFF,
  # plus the 0x80-0x9F specific mappings for Euro, curly quotes, dashes, etc.).
  @unicode_to_winansi %{
    0x20AC => 0x80,
    0x201A => 0x82,
    0x0192 => 0x83,
    0x201E => 0x84,
    0x2026 => 0x85,
    0x2020 => 0x86,
    0x2021 => 0x87,
    0x02C6 => 0x88,
    0x2030 => 0x89,
    0x0160 => 0x8A,
    0x2039 => 0x8B,
    0x0152 => 0x8C,
    0x017D => 0x8E,
    0x2018 => 0x91,
    0x2019 => 0x92,
    0x201C => 0x93,
    0x201D => 0x94,
    0x2022 => 0x95,
    0x2013 => 0x96,
    0x2014 => 0x97,
    0x02DC => 0x98,
    0x2122 => 0x99,
    0x0161 => 0x9A,
    0x203A => 0x9B,
    0x0153 => 0x9C,
    0x017E => 0x9E,
    0x0178 => 0x9F
  }

  defp to_winansi(text) do
    text
    |> String.to_charlist()
    |> Enum.map(&winansi_byte/1)
    |> :erlang.list_to_binary()
  end

  defp winansi_byte(codepoint) when codepoint in 0x00..0xFF, do: codepoint
  defp winansi_byte(codepoint), do: Map.get(@unicode_to_winansi, codepoint, ?\s)
end
