defmodule Press.Layout.BlockTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Block
  alias Press.Style.{Node, Text}

  defp block_node(tag, declarations, children) do
    %Node{
      element: %Press.HTML.Element{tag: tag, attrs: %{}, children: []},
      computed:
        Map.merge(
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
          },
          declarations
        ),
      children: children
    }
  end

  defp text_node(content, font_size \\ 12.0, line_height \\ 14.4) do
    %Text{
      content: content,
      computed: %{
        font_family: :helvetica,
        font_weight: :normal,
        font_style: :normal,
        font_size: font_size,
        line_height: line_height,
        color: {0.0, 0.0, 0.0},
        text_align: :left
      }
    }
  end

  describe "layout_block/4" do
    test "computes block content width as containing_width minus margins, borders, and paddings" do
      node =
        block_node(
          "div",
          %{
            margin: %{top: 10.0, right: 20.0, bottom: 10.0, left: 20.0},
            padding: %{top: 5.0, right: 15.0, bottom: 5.0, left: 15.0},
            border_width: %{top: 1.0, right: 2.0, bottom: 1.0, left: 2.0}
          },
          [text_node("Hello")]
        )

      # containing_width = 300.0
      # content_width = 300 - 20*2 (margin) - 15*2 (padding) - 2*2 (border) = 300 - 40 - 30 - 4 = 226.0
      {box, next_y, _margin_bottom} = Block.layout_block(node, 300.0, 0.0, 0.0)

      assert box.type == :block
      assert box.width == 226.0
      # margin.left
      assert box.x == 20.0
      # margin.top
      assert box.y == 10.0
      assert next_y > 0.0
    end

    test "resolves percentage widths and margins against containing block width" do
      node =
        block_node(
          "div",
          %{
            width: {:percent, 50.0},
            margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: {:percent, 10.0}}
          },
          [text_node("Hello")]
        )

      # containing_width = 400.0
      # width = 50% of 400 = 200.0
      # margin.left = 10% of 400 = 40.0
      {box, _next_y, _margin_bottom} = Block.layout_block(node, 400.0, 0.0, 0.0)

      assert box.width == 200.0
      assert box.margin.left == 40.0
      assert box.x == 40.0
    end

    test "collapses vertical margins between adjacent sibling blocks" do
      node1 =
        block_node(
          "p",
          %{margin: %{top: 0.0, right: 0.0, bottom: 20.0, left: 0.0}},
          [text_node("Paragraph 1", 12.0, 14.0)]
        )

      node2 =
        block_node(
          "p",
          %{margin: %{top: 15.0, right: 0.0, bottom: 0.0, left: 0.0}},
          [text_node("Paragraph 2", 12.0, 14.0)]
        )

      container = block_node("div", %{}, [node1, node2])

      {container_box, _next_y, _margin_bottom} = Block.layout_block(container, 300.0, 0.0, 0.0)

      [b1, b2] = container_box.children

      # b1 height is 14.0, y is 0.0
      # collapsed margin between b1 (bottom 20) and b2 (top 15) is max(20, 15) = 20.0
      # b2.y should be b1.y + b1.height + 20.0 = 0.0 + 14.0 + 20.0 = 34.0
      assert b1.y == 0.0
      assert b1.height == 14.0
      assert b2.y == 34.0
    end

    test "applies vertical-align middle when explicit block height exceeds content height" do
      node =
        block_node(
          "div",
          %{height: 100.0, vertical_align: :middle},
          [text_node("Centered Text", 12.0, 20.0)]
        )

      {box, _next_y, _margin_bottom} = Block.layout_block(node, 300.0, 0.0, 0.0)

      assert box.height == 100.0
      [line] = box.children
      # offset should be (100 - 20) / 2 = 40.0
      assert line.y == 40.0
    end

    test "layouts blocks containing table nodes and inline spans" do
      span = %Node{
        element: %Press.HTML.Element{tag: "span", attrs: %{}, children: []},
        computed: %{
          color: {0.0, 0.0, 0.0},
          font_family: :helvetica,
          font_size: 12.0,
          font_weight: :bold,
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
        },
        children: [text_node("Bold Inline")]
      }

      container = block_node("div", %{}, [span, text_node(" Normal Text")])
      {box, _next_y, _margin_bottom} = Block.layout_block(container, 300.0, 0.0, 0.0)

      assert length(box.children) > 0
    end
  end
end
