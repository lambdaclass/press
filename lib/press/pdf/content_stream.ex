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
        "(#{Syntax.escape_string(text)}) Tj",
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
end
