defmodule Press.HTML.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.HTML.{Element, Parser}

  test "parses a realistic, slightly-imperfect invoice-style fragment" do
    html = """
    <STYLE>table > td { border: 1px solid #000; }</STYLE>
    <div class="invoice">
      <h1>Invoice #123</h1>
      <ul>
        <li>Widget
        <li>Gadget
      </ul>
      <table>
        <tr><td>Widget<td>10.00
        <tr><td>Gadget<td>25.00
      </table>
    </div>
    """

    nodes = Parser.parse(html)

    assert [style] = find_all(nodes, "style")
    assert [text] = style.children
    assert text.content =~ "table > td"

    assert [invoice] = find_all(nodes, "div")
    assert invoice.attrs["class"] == "invoice"

    assert [h1] = find_all(invoice.children, "h1")
    assert [%{content: h1_text}] = h1.children
    assert h1_text =~ "Invoice #123"

    assert [ul] = find_all(invoice.children, "ul")
    assert length(find_all(ul.children, "li")) == 2

    assert [table] = find_all(invoice.children, "table")
    rows = find_all(table.children, "tr")
    assert length(rows) == 2
    assert Enum.all?(rows, fn row -> length(find_all(row.children, "td")) == 2 end)
  end

  defp find_all(nodes, tag) do
    Enum.filter(nodes, &match?(%Element{tag: ^tag}, &1))
  end
end
