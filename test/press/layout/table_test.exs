defmodule Press.Layout.TableTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Table
  alias Press.Style.{Node, Text}

  defp table_node(rows) do
    %Node{
      element: %Press.HTML.Element{tag: "table", attrs: %{}, children: []},
      computed: default_computed(),
      children: rows
    }
  end

  defp row_node(cells) do
    %Node{
      element: %Press.HTML.Element{tag: "tr", attrs: %{}, children: []},
      computed: default_computed(),
      children: cells
    }
  end

  defp cell_node(tag, content, width \\ :auto) do
    %Node{
      element: %Press.HTML.Element{tag: tag, attrs: %{}, children: []},
      computed: Map.put(default_computed(), :width, width),
      children: [
        %Text{
          content: content,
          computed: default_computed()
        }
      ]
    }
  end

  defp default_computed do
    %{
      color: {0.0, 0.0, 0.0},
      font_family: :helvetica,
      font_size: 12.0,
      font_weight: :normal,
      font_style: :normal,
      line_height: 14.4,
      text_align: :left,
      margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      border_color: %{top: nil, right: nil, bottom: nil, left: nil},
      border_style: %{top: :none, right: :none, bottom: :none, left: :none},
      background_color: nil,
      width: :auto,
      height: :auto
    }
  end

  describe "layout_table/4" do
    test "distributes table width evenly across columns when no widths are specified" do
      rows = [
        row_node([cell_node("th", "Col 1"), cell_node("th", "Col 2")]),
        row_node([cell_node("td", "A"), cell_node("td", "B")])
      ]

      table = table_node(rows)

      # Table width = 300.0, 2 columns -> each column is 150.0 wide
      {table_box, next_y, _margin_bottom} = Table.layout_table(table, 300.0, 0.0, 0.0)

      assert table_box.type == :table
      assert table_box.width == 300.0
      assert length(table_box.children) == 2

      [r1, r2] = table_box.children
      [c1_1, c1_2] = r1.children
      [c2_1, c2_2] = r2.children

      assert c1_1.width == 150.0
      assert c1_1.x == 0.0
      assert c1_2.width == 150.0
      assert c1_2.x == 150.0

      assert c2_1.width == 150.0
      assert c2_2.width == 150.0

      assert next_y > 0.0
    end

    test "respects explicit percentage or point column widths" do
      rows = [
        row_node([
          cell_node("td", "30%", {:percent, 30.0}),
          cell_node("td", "70%", {:percent, 70.0})
        ])
      ]

      table = table_node(rows)
      {table_box, _next_y, _margin_bottom} = Table.layout_table(table, 400.0, 0.0, 0.0)

      [row] = table_box.children
      [c1, c2] = row.children

      # 30% of 400
      assert c1.width == 120.0
      # 70% of 400
      assert c2.width == 280.0
    end

    test "synchronizes cell heights across the same row to the maximum cell height" do
      # In Courier 10pt (char width 6pt), line height 12pt:
      # "Short" (30pt) in 60pt column -> 1 line (14.4pt)
      # "Line 1 Line 2 Line 3" in 60pt column -> wraps into 3 lines (43.2pt)
      c1 = cell_node("td", "Short", 60.0)
      c2 = cell_node("td", "Line 1 Line 2 Line 3", 60.0)

      rows = [row_node([c1, c2])]
      table = table_node(rows)

      {table_box, _next_y, _margin_bottom} = Table.layout_table(table, 200.0, 0.0, 0.0)

      [row] = table_box.children
      [cell1, cell2] = row.children

      assert cell1.height == cell2.height
      assert cell1.height > 14.4
    end

    test "handles thead, tbody, and tfoot sections with colspan" do
      th_cell = %Node{
        element: %Press.HTML.Element{tag: "th", attrs: %{"colspan" => "2"}, children: []},
        computed: default_computed(),
        children: [%Text{content: "Header", computed: default_computed()}]
      }

      th_row = %Node{
        element: %Press.HTML.Element{tag: "tr", attrs: %{}, children: []},
        computed: default_computed(),
        children: [th_cell]
      }

      thead = %Node{
        element: %Press.HTML.Element{tag: "thead", attrs: %{}, children: []},
        computed: default_computed(),
        children: [th_row]
      }

      td_cell1 = cell_node("td", "A")
      td_cell2 = cell_node("td", "B")
      tb_row = row_node([td_cell1, td_cell2])

      tbody = %Node{
        element: %Press.HTML.Element{tag: "tbody", attrs: %{}, children: []},
        computed: default_computed(),
        children: [tb_row]
      }

      table = %Node{
        element: %Press.HTML.Element{tag: "table", attrs: %{}, children: []},
        computed: default_computed(),
        children: [thead, tbody]
      }

      {table_box, _next_y, _margin_bottom} = Table.layout_table(table, 300.0, 0.0, 0.0)

      assert length(table_box.children) == 2
      [r1, r2] = table_box.children
      [header_cell] = r1.children
      assert header_cell.width == 300.0
      assert length(r2.children) == 2
    end
  end

  describe "rows with fewer cells than the table has columns" do
    test "a short row does not leak the reduce accumulator as a column width" do
      rows = [
        row_node([cell_node("th", "A"), cell_node("th", "B"), cell_node("th", "C")]),
        row_node([cell_node("td", "solo una")])
      ]

      {table_box, _next_y, _mb} = Table.layout_table(table_node(rows), 300.0, 0.0, 0.0)

      for row <- table_box.children, cell <- row.children do
        assert is_number(cell.width)
        assert cell.width > 0.0
      end
    end
  end
end
