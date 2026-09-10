defmodule Press.Style.CustomPropertiesTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Style.Cascade

  # Custom properties are resolved during the cascade, so the assertions read
  # the computed value off the styled tree rather than the parsed rule.
  defp computed(body, css, tag) do
    full_css = "@page { size: 600pt 800pt; margin: 0pt }\n#{css}"
    html = "<html><head><style>#{full_css}</style></head><body>#{body}</body></html>"
    {_page_rules, style_rules} = CSSParser.parse(full_css)

    HTMLParser.parse(html)
    |> Cascade.build([], style_rules)
    |> find(tag)
    |> Map.fetch!(:computed)
  end

  defp find(nodes, tag) when is_list(nodes) do
    Enum.find_value(nodes, fn node -> find(node, tag) end)
  end

  defp find(%Press.Style.Node{element: %{tag: tag}} = node, tag), do: node
  defp find(%Press.Style.Node{children: children}, tag), do: find(children, tag)
  defp find(_other, _tag), do: nil

  describe "var()" do
    test "resolves a property declared on :root" do
      c = computed("<p>x</p>", ":root { --ink: #ff0000 } p { color: var(--ink) }", "p")
      assert c.color == {1.0, 0.0, 0.0}
    end

    test "resolves a property declared on an ancestor's inline style" do
      c =
        computed(
          ~s(<div style="--ink: #0000ff"><p>x</p></div>),
          "p { color: var(--ink) }",
          "p"
        )

      assert c.color == {0.0, 0.0, 1.0}
    end

    test "a nearer declaration wins over :root" do
      c =
        computed(
          ~s(<div style="--ink: #00ff00"><p>x</p></div>),
          ":root { --ink: #ff0000 } p { color: var(--ink) }",
          "p"
        )

      assert c.color == {0.0, 1.0, 0.0}
    end

    test "works inside a shorthand" do
      c =
        computed(
          "<div>x</div>",
          ":root { --rule: #ff0000 } div { border-top: 2pt solid var(--rule) }",
          "div"
        )

      assert c.border_color.top == {1.0, 0.0, 0.0}
      assert c.border_width.top == 2.0
    end

    test "falls back to the second argument when the property is not declared" do
      c = computed("<p>x</p>", "p { color: var(--nope, #ff0000) }", "p")
      assert c.color == {1.0, 0.0, 0.0}
    end

    test "an unresolvable reference drops the declaration instead of the element" do
      c = computed("<p>x</p>", "p { color: var(--nope) }", "p")
      assert c.color == {0.0, 0.0, 0.0}
    end

    test "custom properties do not leak into the computed style as properties" do
      c = computed("<p>x</p>", ":root { --ink: #ff0000 } p { color: var(--ink) }", "p")
      refute Enum.any?(Map.keys(c), &(is_binary(&1) and String.starts_with?(&1, "--")))
    end
  end

  describe "ch and ex units" do
    test "ch resolves against the font size" do
      c = computed("<p>x</p>", "p { font-size: 10pt; min-width: 10ch }", "p")
      assert c.min_width == 50.0
    end
  end
end
