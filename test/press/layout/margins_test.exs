defmodule Press.Layout.MarginsTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Layout
  alias Press.Style.Cascade

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
    if box.tag == tag,
      do: box,
      else: Enum.find_value(box.children, fn child -> find(child, tag) end)
  end

  describe "parent-child margin collapsing" do
    test "a wrapper's first child pushes the wrapper down instead of indenting inside it" do
      root = layout(~s(<p>a</p><section><h2>b</h2></section>), "h2 { margin-top: 20pt }")

      section = find(root, "section")
      h2 = find(root, "h2")

      # The heading's margin lands outside the section, so the two share a top
      # edge instead of the section opening a 20pt gap of its own.
      assert h2.y == section.y

      # And it is the heading's 20pt that opens the gap, not the paragraph's
      # own 1em bottom margin, which is smaller and collapses into it.
      paragraph = find(root, "p")
      assert_in_delta section.y - (paragraph.y + paragraph.height), 20.0, 0.5
    end

    test "a top border keeps the two margins apart" do
      root =
        layout(
          ~s(<p>a</p><section><h2>b</h2></section>),
          "h2 { margin-top: 20pt } section { border-top: 1pt solid #000 }"
        )

      section = find(root, "section")
      h2 = find(root, "h2")

      assert h2.y > section.y
    end

    test "the larger of the two margins wins" do
      small = layout(~s(<p>a</p><section><h2>b</h2></section>), "h2 { margin-top: 5pt }")
      large = layout(~s(<p>a</p><section><h2>b</h2></section>), "h2 { margin-top: 40pt }")

      assert find(large, "section").y > find(small, "section").y
    end
  end
end
