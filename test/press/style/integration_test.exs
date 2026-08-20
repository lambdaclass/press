defmodule Press.Style.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Element
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Style.{Cascade, Node}

  test "parses and cascades a fragment combining the UA stylesheet, an external stylesheet, and embedded <style>" do
    html = """
    <style>.total { color: red; }</style>
    <h1>Invoice #123</h1>
    <p class="total">Total: 100</p>
    """

    external_css = "p { font-size: 14px; }"

    dom = HTMLParser.parse(html)
    {_ext_page_rules, external_rules} = CSSParser.parse(external_css)

    embedded_css =
      dom
      |> find_dom("style")
      |> Enum.map_join("\n", fn %{children: [%Press.HTML.Text{content: content}]} -> content end)

    {_emb_page_rules, embedded_rules} = CSSParser.parse(embedded_css)

    styled = Cascade.build(dom, external_rules, embedded_rules)

    [h1] = find_styled(styled, "h1")
    assert h1.computed.font_size == 24.0

    [p] = find_styled(styled, "p")
    assert_in_delta p.computed.font_size, 10.5, 0.01
    assert p.computed.color == {1.0, 0.0, 0.0}
  end

  # Pre-cascade: filters Press.HTML.Element nodes from Press.HTML.Parser's output.
  defp find_dom(nodes, tag) do
    Enum.filter(nodes, &match?(%Element{tag: ^tag}, &1))
  end

  # Post-cascade: filters Press.Style.Node nodes from Press.Style.Cascade.build/3's output.
  defp find_styled(nodes, tag) do
    Enum.filter(nodes, &match?(%Node{element: %{tag: ^tag}}, &1))
  end
end
