defmodule Press.Layout.GridTest do
  use ExUnit.Case, async: true

  alias Press.HTML.Element
  alias Press.Layout.Grid
  alias Press.Style.{Node, Text}

  defp make_node(tag, class, children) do
    %Node{
      element: %Element{tag: tag, attrs: %{"class" => class}},
      computed: %{
        margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        border_color: nil,
        border_style: :none,
        background_color: nil,
        width: :auto,
        height: :auto,
        font_size: 12.0,
        font_family: :helvetica,
        font_weight: :normal,
        font_style: :normal,
        text_align: :left
      },
      children: children
    }
  end

  defp make_text(content) do
    %Text{
      content: content,
      computed: %{
        font_size: 12.0,
        font_family: :helvetica,
        font_weight: :normal,
        font_style: :normal,
        color: {0.0, 0.0, 0.0},
        line_height: 14.4
      }
    }
  end

  describe "layout_grid/5" do
    test "places col-span-7 and col-span-5 side-by-side on the same row" do
      col1 = make_node("div", "col-span-7", [make_text("Left Side")])
      col2 = make_node("div", "col-span-5", [make_text("Right Side")])
      grid = make_node("div", "grid grid-cols-12 gap-4", [col1, col2])

      {box, _next_y, _m} = Grid.layout_grid(grid, 600.0, 0.0, 0.0)

      assert length(box.children) == 2
      [box1, box2] = box.children

      assert box1.x == 0.0
      assert box2.x > box1.x
      assert box1.y == 0.0
      assert box2.y == 0.0
    end

    test "wraps columns exceeding 12 columns to the next row" do
      col1 = make_node("div", "col-span-7", [make_text("Row 1 Left")])
      col2 = make_node("div", "col-span-5", [make_text("Row 1 Right")])
      col3 = make_node("div", "col-span-12", [make_text("Row 2 Full")])
      grid = make_node("div", "grid grid-cols-12 gap-4", [col1, col2, col3])

      {box, _next_y, _m} = Grid.layout_grid(grid, 600.0, 0.0, 0.0)

      assert length(box.children) == 3
      [box1, box2, box3] = box.children

      assert box1.y == 0.0
      assert box2.y == 0.0
      assert box3.y > 0.0
      assert box3.x == 0.0
    end
  end
end
