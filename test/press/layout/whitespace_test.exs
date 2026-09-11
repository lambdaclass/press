defmodule Press.Layout.WhitespaceTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Whitespace

  test "collapsible runs are blank" do
    assert Whitespace.blank?("")
    assert Whitespace.blank?("   ")
    assert Whitespace.blank?("\n\t \r")
  end

  test "a non-breaking space prints, so it is not blank" do
    refute Whitespace.blank?(<<0xA0::utf8>>)
    refute Whitespace.blank?(" " <> <<0xA0::utf8>> <> " ")
  end

  test "an empty cell holding only &nbsp; still gets a line box" do
    html = """
    <html><head><style>
    * { margin: 0; padding: 0 }
    td { padding: 0; font-size: 10px; line-height: 20px }
    </style></head><body><table><tbody>
    <tr><td>&nbsp;</td></tr>
    </tbody></table></body></html>
    """

    {:ok, pdf} = Press.render(html)
    assert byte_size(pdf) > 0

    dom = Press.HTML.Parser.parse(html)
    {page_css, rules} = Press.CSS.Parser.parse(embedded_css(dom))
    config = Press.Style.Cascade.page_config([], page_css)
    root = Press.Layout.build(Press.Style.Cascade.build(dom, [], rules), config, %{})

    [cell] = find_boxes(root, :table_cell)
    assert cell.height >= 15.0
  end

  defp embedded_css(nodes) do
    nodes
    |> Enum.flat_map(fn
      %Press.HTML.Element{tag: "style", children: ch} ->
        Enum.map(ch, fn %Press.HTML.Text{content: c} -> c end)

      %Press.HTML.Element{children: ch} ->
        [embedded_css(ch)]

      _ ->
        []
    end)
    |> Enum.join("\n")
  end

  defp find_boxes(box, type) do
    own = if box.type == type, do: [box], else: []
    own ++ Enum.flat_map(box.children || [], &find_boxes(&1, type))
  end
end
