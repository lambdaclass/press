defmodule Press.PDF.ContentStream do
  @moduledoc false

  alias Press.PDF.Syntax

  def render(ops, font_resource_names) do
    Enum.map_join(ops, "\n", &render_op(&1, font_resource_names))
  end

  defp render_op({:text, x, y, font, size, {r, g, b}, text}, font_resource_names) do
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

  defp render_op({:rect, x, y, w, h, fill, stroke, stroke_width}, _font_resource_names) do
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

  # WinAnsiEncoding is essentially Windows-1252, which matches Latin-1
  # (ISO-8859-1) for 0x00-0x7F and 0xA0-0xFF. PDF string literals for the
  # base-14 fonts are single-byte, so UTF-8 text must be converted before
  # being embedded. The 0x80-0x9F Windows-1252-specific block (curly
  # quotes, em-dash, euro sign, etc.) is out of scope for Phase 1.
  defp to_winansi(text) do
    text
    |> String.to_charlist()
    |> Enum.map(&winansi_byte/1)
    |> :erlang.list_to_binary()
  end

  defp winansi_byte(codepoint) when codepoint in 0x00..0xFF, do: codepoint
  defp winansi_byte(_codepoint), do: ?\s
end
