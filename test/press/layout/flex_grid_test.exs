defmodule Press.Layout.FlexGridTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Layout
  alias Press.Layout.Box
  alias Press.Style.Cascade

  # Lays a document out and hands back the box whose tag/class is asked for, so
  # the assertions can talk about geometry instead of tree walking.
  defp layout(body, css) do
    full_css = """
    @page { size: 600pt 800pt; margin: 0pt }
    body { font-family: Helvetica; font-size: 10pt; line-height: 1 }
    #{css}
    """

    html = "<html><head><style>#{full_css}</style></head><body>#{body}</body></html>"
    {page_rules, style_rules} = CSSParser.parse(full_css)

    HTMLParser.parse(html)
    |> Cascade.build([], style_rules)
    |> Layout.build(Cascade.page_config([], page_rules), %{})
  end

  defp find(box, tag) do
    if box.tag == tag do
      box
    else
      Enum.find_value(box.children, fn child -> find(child, tag) end)
    end
  end

  defp cells(root, container_tag) do
    find(root, container_tag).children
  end

  defp widths(boxes), do: Enum.map(boxes, &Float.round(&1.width * 1.0, 1))
  defp xs(boxes), do: Enum.map(boxes, &Float.round(&1.x * 1.0, 1))

  describe "grid tracks" do
    test "fr tracks split the content box in proportion" do
      root =
        layout(
          ~s(<div class="g"><p>a</p><p>b</p><p>c</p></div>),
          ".g { display: grid; grid-template-columns: 1fr 2fr 1fr }"
        )

      assert widths(cells(root, "div")) == [150.0, 300.0, 150.0]
    end

    test "a px track keeps its size and fr tracks share what is left" do
      root =
        layout(
          ~s(<div class="g"><p>a</p><p>b</p><p>c</p></div>),
          ".g { display: grid; grid-template-columns: 1fr 200px 1fr }"
        )

      # 200px is 150pt, leaving 450pt for the two fr tracks.
      assert widths(cells(root, "div")) == [225.0, 150.0, 225.0]
    end

    test "repeat() expands into that many identical tracks" do
      root =
        layout(
          ~s(<div class="g"><p>a</p><p>b</p><p>c</p><p>d</p></div>),
          ".g { display: grid; grid-template-columns: repeat(4, 1fr) }"
        )

      assert widths(cells(root, "div")) == [150.0, 150.0, 150.0, 150.0]
    end

    test "column-gap is taken out of the tracks, not added to the container" do
      root =
        layout(
          ~s(<div class="g"><p>a</p><p>b</p></div>),
          ".g { display: grid; grid-template-columns: 1fr 1fr; gap: 20pt }"
        )

      boxes = cells(root, "div")
      assert widths(boxes) == [290.0, 290.0]
      assert xs(boxes) == [0.0, 310.0]
    end

    test "an auto track is as wide as its widest content" do
      root =
        layout(
          ~s(<div class="g"><p>iiii</p><p>rest</p></div>),
          ".g { display: grid; grid-template-columns: auto 1fr }"
        )

      [auto_col, fr_col] = cells(root, "div")
      assert auto_col.width > 0.0
      assert auto_col.width < 100.0
      assert_in_delta auto_col.width + fr_col.width, 600.0, 0.5
    end

    test "children wrap onto a second row once the tracks are full" do
      root =
        layout(
          ~s(<div class="g"><p>a</p><p>b</p><p>c</p><p>d</p></div>),
          ".g { display: grid; grid-template-columns: 1fr 1fr }"
        )

      boxes = cells(root, "div")
      assert length(boxes) == 4
      assert xs(boxes) == [0.0, 300.0, 0.0, 300.0]
      [a, _b, c, _d] = boxes
      assert c.y > a.y
    end
  end

  describe "grid align-items" do
    test "stretch grows every cell to the tallest in its row" do
      root =
        layout(
          ~s(<div class="g"><div class="tall"><p>a</p><p>b</p></div><div class="short"><p>c</p></div></div>),
          """
          .g { display: grid; grid-template-columns: 1fr 1fr }
          .tall p { line-height: 20pt }
          """
        )

      [tall, short] = cells(root, "div")
      assert Box.outer_height(short) == Box.outer_height(tall)
    end

    test "center leaves the cell at its own height and offsets it" do
      root =
        layout(
          ~s(<div class="g"><div class="tall"><p>a</p><p>b</p></div><div class="short"><p>c</p></div></div>),
          """
          .g { display: grid; grid-template-columns: 1fr 1fr; align-items: center }
          .tall p { line-height: 20pt }
          """
        )

      [tall, short] = cells(root, "div")
      assert Box.outer_height(short) < Box.outer_height(tall)
      assert short.y > tall.y
    end
  end

  describe "flex" do
    test "row places children side by side in source order" do
      root =
        layout(
          ~s(<div class="f"><p>uno</p><p>dos</p></div>),
          ".f { display: flex }"
        )

      [a, b] = cells(root, "div")
      assert a.x == 0.0
      assert b.x > a.x
      assert b.y == a.y
    end

    test "flex-grow shares the leftover main-axis space" do
      root =
        layout(
          ~s(<div class="f"><div class="c"><p>a</p></div><div class="c"><p>b</p></div></div>),
          """
          .f { display: flex }
          .c { flex: 1 }
          """
        )

      assert widths(cells(root, "div")) == [300.0, 300.0]
    end

    test "justify-content: center centres the row within the container" do
      root =
        layout(
          ~s(<div class="f"><p>x</p></div>),
          ".f { display: flex; justify-content: center }"
        )

      [only] = cells(root, "div")
      assert only.x > 0.0
      assert_in_delta only.x + only.width / 2.0, 300.0, 1.0
    end

    test "column stacks children and align-items: center centres each one" do
      root =
        layout(
          ~s(<div class="f"><p>corto</p><p>mucho mas largo</p></div>),
          ".f { display: flex; flex-direction: column; align-items: center }"
        )

      [a, b] = cells(root, "div")
      assert b.y > a.y
      assert a.x > 0.0
      assert_in_delta a.x + a.width / 2.0, 300.0, 1.0
      assert_in_delta b.x + b.width / 2.0, 300.0, 1.0
    end

    test "a column with justify-content: center distributes min-height slack" do
      tight =
        layout(
          ~s(<div class="f"><p>x</p></div>),
          ".f { display: flex; flex-direction: column; justify-content: center }"
        )

      roomy =
        layout(
          ~s(<div class="f"><p>x</p></div>),
          ".f { display: flex; flex-direction: column; justify-content: center; min-height: 200pt }"
        )

      [tight_child] = cells(tight, "div")
      [roomy_child] = cells(roomy, "div")

      assert find(roomy, "div").height >= 200.0
      assert roomy_child.y > tight_child.y
    end
  end

  describe "display: none" do
    test "removes the element and its subtree from the flow" do
      root = layout(~s(<p class="h">oculto</p><p>visible</p>), ".h { display: none }")
      assert length(root.children) == 1
      assert find(root, "p") != nil
    end
  end

  describe "box-sizing" do
    test "border-box takes padding out of the declared width" do
      content = layout(~s(<div class="b">x</div>), ".b { width: 200pt; padding: 10pt }")

      border =
        layout(
          ~s(<div class="b">x</div>),
          ".b { width: 200pt; padding: 10pt; box-sizing: border-box }"
        )

      assert find(content, "div").width == 200.0
      assert find(border, "div").width == 180.0
    end
  end
end
