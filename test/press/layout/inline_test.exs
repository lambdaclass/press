defmodule Press.Layout.InlineTest do
  use ExUnit.Case, async: true

  alias Press.Layout.Inline
  alias Press.Style.{Node, Text}

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

  describe "wrap/3" do
    test "wraps text into a single line when it fits within available width" do
      nodes = [text_node("Hello world")]
      lines = Inline.wrap(nodes, 200.0, :left)

      assert length(lines) == 1
      [line] = lines
      assert line.type == :line
      assert line.height == 14.4
      assert line.width < 200.0

      # Words are placed on the line
      texts = Enum.map(line.children, & &1.text)
      assert texts == ["Hello", " ", "world"]
    end

    test "wraps text into multiple lines when it exceeds available width" do
      # In Courier 10pt, each char is 6pt. "Word1 Word2 Word3" is 17 chars = 102pt
      node = %Text{
        content: "Word1 Word2 Word3",
        computed: %{
          font_family: :courier,
          font_weight: :normal,
          font_style: :normal,
          font_size: 10.0,
          line_height: 12.0,
          color: {0.0, 0.0, 0.0},
          text_align: :left
        }
      }

      # Available width 50pt fits "Word1" (30pt) but not "Word1 Word2" (66pt)
      lines = Inline.wrap([node], 50.0, :left)

      assert length(lines) == 3
      [l1, l2, l3] = lines
      assert Enum.map(l1.children, & &1.text) == ["Word1"]
      assert Enum.map(l2.children, & &1.text) == ["Word2"]
      assert Enum.map(l3.children, & &1.text) == ["Word3"]
    end

    test "collapses multiple consecutive whitespace characters" do
      nodes = [text_node("Hello    \n\t   world")]
      [line] = Inline.wrap(nodes, 200.0, :left)

      texts = Enum.map(line.children, & &1.text)
      assert texts == ["Hello", " ", "world"]
    end

    test "applies center and right text alignment" do
      node = %Text{
        content: "Hello",
        computed: %{
          font_family: :courier,
          font_weight: :normal,
          font_style: :normal,
          font_size: 10.0,
          line_height: 12.0,
          color: {0.0, 0.0, 0.0},
          text_align: :left
        }
      }

      # "Hello" in Courier 10pt is 30pt. Available width is 100pt.
      [left_line] = Inline.wrap([node], 100.0, :left)
      [center_line] = Inline.wrap([node], 100.0, :center)
      [right_line] = Inline.wrap([node], 100.0, :right)

      [left_box] = left_line.children
      [center_box] = center_line.children
      [right_box] = right_line.children

      assert left_box.x == 0.0
      # (100 - 30) / 2 = 35
      assert_in_delta center_box.x, 35.0, 0.01
      # 100 - 30 = 70
      assert_in_delta right_box.x, 70.0, 0.01
    end

    test "handles inline element styling with different font weights and colors" do
      nodes = [
        %Text{
          content: "Normal ",
          computed: %{
            font_family: :helvetica,
            font_weight: :normal,
            font_style: :normal,
            font_size: 12.0,
            line_height: 14.4,
            color: {0.0, 0.0, 0.0}
          }
        },
        %Node{
          element: %Press.HTML.Element{tag: "strong", attrs: %{}, children: []},
          computed: %{
            font_family: :helvetica,
            font_weight: :bold,
            font_style: :normal,
            font_size: 12.0,
            line_height: 14.4,
            color: {1.0, 0.0, 0.0}
          },
          children: [
            %Text{
              content: "Bold",
              computed: %{
                font_family: :helvetica,
                font_weight: :bold,
                font_style: :normal,
                font_size: 12.0,
                line_height: 14.4,
                color: {1.0, 0.0, 0.0}
              }
            }
          ]
        }
      ]

      [line] = Inline.wrap(nodes, 200.0, :left)
      [normal_box, _space_box, bold_box] = line.children

      assert normal_box.font == :helvetica
      assert normal_box.color == {0.0, 0.0, 0.0}
      assert bold_box.font == :helvetica_bold
      assert bold_box.color == {1.0, 0.0, 0.0}
    end
  end
end
