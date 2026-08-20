defmodule Press.Style.CascadeTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Rule
  alias Press.HTML
  alias Press.Style.{Cascade, Node, Text}

  defp rule(selector_text, specificity, declarations, source_index \\ 0) do
    %Rule{
      selector: Press.CSS.Selector.parse(selector_text),
      specificity: specificity,
      declarations: declarations,
      source_index: source_index
    }
  end

  test "matches a rule and applies its declarations" do
    dom = [%HTML.Element{tag: "p", attrs: %{}, children: []}]
    rules = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.color == {1.0, 0.0, 0.0}
  end

  test "merges declarations per property across multiple matching rules by specificity" do
    dom = [%HTML.Element{tag: "p", attrs: %{"class" => "note"}, children: []}]

    rules = [
      rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}, "font-weight" => :bold}),
      rule(".note", {0, 1, 0}, %{"color" => {0.0, 0.0, 1.0}})
    ]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.color == {0.0, 0.0, 1.0}
    assert computed.font_weight == :bold
  end

  test "embedded <style> rules beat opts[:css] rules at equal specificity" do
    dom = [%HTML.Element{tag: "p", attrs: %{}, children: []}]
    external = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]
    embedded = [rule("p", {0, 0, 1}, %{"color" => {0.0, 1.0, 0.0}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, external, embedded)
    assert computed.color == {0.0, 1.0, 0.0}
  end

  test "inherits color from parent when a child doesn't set it" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [%HTML.Element{tag: "span", attrs: %{}, children: []}]
      }
    ]

    rules = [rule("div", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{computed: parent_computed, children: [%Node{computed: child_computed}]}] =
             Cascade.build(dom, rules, [])

    assert parent_computed.color == {1.0, 0.0, 0.0}
    assert child_computed.color == {1.0, 0.0, 0.0}
  end

  test "em resolves against the node's own resolved font-size, which may come from its parent" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [%HTML.Element{tag: "span", attrs: %{}, children: []}]
      }
    ]

    rules = [
      rule("div", {0, 0, 1}, %{"font-size" => {:length, 20.0, :pt}}),
      rule("span", {0, 0, 1}, %{"margin-top" => {:length, 2.0, :em}})
    ]

    assert [%Node{children: [%Node{computed: child_computed}]}] = Cascade.build(dom, rules, [])
    assert child_computed.font_size == 20.0
    assert child_computed.margin.top == 40.0
  end

  test "% stays symbolic instead of being resolved" do
    dom = [%HTML.Element{tag: "div", attrs: %{}, children: []}]
    rules = [rule("div", {0, 0, 1}, %{"margin-left" => {:length, 50.0, :percent}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.margin.left == {:percent, 50.0}
  end

  test "line-height inherits the specified multiplier, not the parent's resolved points" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [
          %HTML.Element{
            tag: "span",
            attrs: %{},
            children: []
          }
        ]
      }
    ]

    rules = [
      rule("div", {0, 0, 1}, %{
        "line-height" => {:line_height, :multiplier, 1.5},
        "font-size" => {:length, 10.0, :pt}
      }),
      rule("span", {0, 0, 1}, %{"font-size" => {:length, 20.0, :pt}})
    ]

    assert [%Node{computed: parent_computed, children: [%Node{computed: child_computed}]}] =
             Cascade.build(dom, rules, [])

    assert parent_computed.line_height == 15.0
    assert child_computed.line_height == 30.0
  end

  test "a bare fragment with multiple top-level siblings has no common root" do
    dom = [
      %HTML.Element{tag: "h1", attrs: %{}, children: []},
      %HTML.Text{content: "hello"}
    ]

    assert [%Node{}, %Text{content: "hello"}] = Cascade.build(dom, [], [])
  end

  test "a text node carries its parent's inherited computed values" do
    dom = [
      %HTML.Element{
        tag: "p",
        attrs: %{},
        children: [%HTML.Text{content: "hi"}]
      }
    ]

    rules = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{children: [%Text{content: "hi", computed: text_computed}]}] =
             Cascade.build(dom, rules, [])

    assert text_computed.color == {1.0, 0.0, 0.0}
  end
end
