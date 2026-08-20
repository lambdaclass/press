defmodule Press.LayoutTest do
  use ExUnit.Case, async: true

  alias Press.Layout
  alias Press.Layout.Box
  alias Press.Style.{Node, Text}

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

  defp page_config do
    %{
      size: {595.28, 841.89},
      margin: %{top: 56.69, right: 56.69, bottom: 56.69, left: 56.69}
    }
  end

  describe "build/2" do
    test "skips non-visual elements such as style, link, meta, head, script" do
      styled_tree = [
        %Node{
          element: %Press.HTML.Element{tag: "head", attrs: %{}, children: []},
          computed: default_computed(),
          children: [
            %Node{
              element: %Press.HTML.Element{tag: "style", attrs: %{}, children: []},
              computed: default_computed(),
              children: [%Text{content: "body { color: red; }", computed: default_computed()}]
            }
          ]
        },
        %Node{
          element: %Press.HTML.Element{tag: "h1", attrs: %{}, children: []},
          computed: default_computed(),
          children: [%Text{content: "Invoice", computed: default_computed()}]
        }
      ]

      root = Layout.build(styled_tree, page_config())

      assert %Box{type: :root} = root
      # Only h1 should be present in root.children
      assert length(root.children) == 1
      [h1_box] = root.children
      assert h1_box.tag == "h1"
    end

    test "lays out mixed blocks and tables into a positioned tree" do
      styled_tree = [
        %Node{
          element: %Press.HTML.Element{tag: "h1", attrs: %{}, children: []},
          computed: Map.put(default_computed(), :margin, %{top: 0.0, right: 0.0, bottom: 10.0, left: 0.0}),
          children: [%Text{content: "Title", computed: default_computed()}]
        },
        %Node{
          element: %Press.HTML.Element{tag: "table", attrs: %{}, children: []},
          computed: default_computed(),
          children: [
            %Node{
              element: %Press.HTML.Element{tag: "tr", attrs: %{}, children: []},
              computed: default_computed(),
              children: [
                %Node{
                  element: %Press.HTML.Element{tag: "td", attrs: %{}, children: []},
                  computed: default_computed(),
                  children: [%Text{content: "Item", computed: default_computed()}]
                }
              ]
            }
          ]
        }
      ]

      root = Layout.build(styled_tree, page_config())

      assert %Box{type: :root} = root
      assert length(root.children) == 2
      [h1_box, table_box] = root.children

      assert h1_box.tag == "h1"
      assert table_box.type == :table
      assert table_box.y >= h1_box.y + h1_box.height
    end
  end
end
