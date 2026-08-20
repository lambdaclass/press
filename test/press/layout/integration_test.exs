defmodule Press.Layout.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Layout
  alias Press.Layout.Box
  alias Press.Style.Cascade

  test "lays out a complete HTML document with embedded and external CSS into positioned boxes" do
    html = """
    <!DOCTYPE html>
    <html>
      <head>
        <style>
          @page { size: A4; margin: 20mm; }
          body { font-family: helvetica; font-size: 12pt; }
          h1 { color: red; font-size: 24pt; margin-bottom: 10pt; }
          p.intro { font-size: 14pt; margin-bottom: 20pt; }
          table { width: 100%; }
          th { font-weight: bold; background-color: #eee; }
        </style>
      </head>
      <body>
        <h1>Invoice #123</h1>
        <p class="intro">Billed to: Acme Corp</p>
        <table>
          <thead>
            <tr>
              <th style="width: 70%">Item</th>
              <th style="width: 30%">Amount</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Consulting Services</td>
              <td>$1,500.00</td>
            </tr>
          </tbody>
        </table>
      </body>
    </html>
    """

    dom = HTMLParser.parse(html)

    # Extract embedded style blocks
    style_content =
      dom
      |> find_all_tag("style")
      |> Enum.map_join("\n", fn %{children: [%Press.HTML.Text{content: c}]} -> c end)

    {page_rules, css_rules} = CSSParser.parse(style_content)

    # Cascade
    page_config = Cascade.page_config(page_rules, [])
    styled_tree = Cascade.build(dom, css_rules, [])

    # Layout
    root_box = Layout.build(styled_tree, page_config)

    assert %Box{type: :root} = root_box
    # A4 is 595.28 x 841.89 pt, 20mm margin is ~56.69 pt on each side
    # Usable width = 595.28 - 2 * 56.69 = ~481.89 pt
    assert_in_delta root_box.width, 481.89, 0.5
    assert_in_delta root_box.x, 56.69, 0.1
    assert_in_delta root_box.y, 56.69, 0.1

    # Children: h1, p.intro, table
    assert length(root_box.children) == 3
    [h1_box, p_box, table_box] = root_box.children

    # H1
    assert h1_box.tag == "h1"
    assert_in_delta h1_box.y, root_box.y + h1_box.margin.top, 0.1

    # P intro
    assert p_box.tag == "p"
    assert p_box.y > h1_box.y

    # Table
    assert table_box.type == :table
    assert table_box.y > p_box.y
    assert_in_delta table_box.width, root_box.width, 0.1

    # Check table rows and cells
    [thead_row, tbody_row] = table_box.children
    [th1, th2] = thead_row.children
    [td1, td2] = tbody_row.children

    assert_in_delta th1.width, root_box.width * 0.7, 0.1
    assert_in_delta th2.width, root_box.width * 0.3, 0.1
    assert_in_delta td1.width, root_box.width * 0.7, 0.1
    assert_in_delta td2.width, root_box.width * 0.3, 0.1
  end

  defp find_all_tag(nodes, tag) do
    Enum.flat_map(nodes, fn
      %Press.HTML.Element{tag: ^tag} = el -> [el]
      %Press.HTML.Element{children: children} -> find_all_tag(children, tag)
      _ -> []
    end)
  end
end
