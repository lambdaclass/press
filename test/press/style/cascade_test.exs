defmodule Press.Style.CascadeTest do
  use ExUnit.Case, async: true

  alias Press.CSS.{PageRule, Rule}
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

  describe "page_config/2" do
    test "defaults to A4 with 20mm margins when no @page rules are given" do
      config = Cascade.page_config([], [])

      assert_in_delta elem(config.size, 0), 595.28, 0.1
      assert_in_delta elem(config.size, 1), 841.89, 0.1
      assert_in_delta config.margin.top, 56.69, 0.1
      assert_in_delta config.margin.right, 56.69, 0.1
    end

    test "uses the last rule to set each of size/margin, across origins" do
      external = [%PageRule{declarations: %{"size" => :letter}, source_index: 0}]

      embedded_margin = %{
        top: {:length, 10.0, :mm},
        right: {:length, 10.0, :mm},
        bottom: {:length, 10.0, :mm},
        left: {:length, 10.0, :mm}
      }

      embedded = [%PageRule{declarations: %{"margin" => embedded_margin}, source_index: 0}]

      config = Cascade.page_config(external, embedded)

      assert config.size == {612.0, 792.0}
      assert_in_delta config.margin.top, 28.35, 0.1
    end

    test "resolves a custom two-length size" do
      custom = {:custom, {:length, 210.0, :mm}, {:length, 297.0, :mm}}
      external = [%PageRule{declarations: %{"size" => custom}, source_index: 0}]

      config = Cascade.page_config(external, [])

      assert_in_delta elem(config.size, 0), 595.28, 0.1
      assert_in_delta elem(config.size, 1), 841.89, 0.1
    end

    test "resolves legal page size" do
      external = [%PageRule{declarations: %{"size" => :legal}, source_index: 0}]
      config = Cascade.page_config(external, [])
      assert config.size == {612.0, 1008.0}
    end
  end

  describe "units and inline styles" do
    test "parses and applies inline style attribute over CSS rules" do
      dom = [
        %HTML.Element{
          tag: "p",
          attrs: %{"style" => "color: blue; margin-top: 15px;"},
          children: []
        }
      ]

      rules = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

      assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
      assert computed.color == {0.0, 0.0, 1.0}
      assert computed.margin.top == 15.0 * 0.75
    end

    test "applies text-transform to text nodes" do
      dom_upper = [
        %HTML.Element{
          tag: "p",
          attrs: %{"style" => "text-transform: uppercase;"},
          children: [%HTML.Text{content: "hello"}]
        }
      ]

      assert [%Node{children: [%Text{content: "HELLO"}]}] = Cascade.build(dom_upper, [], [])

      dom_cap = [
        %HTML.Element{
          tag: "p",
          attrs: %{"style" => "text-transform: capitalize;"},
          children: [%HTML.Text{content: "hello"}]
        }
      ]

      assert [%Node{children: [%Text{content: "Hello"}]}] = Cascade.build(dom_cap, [], [])

      dom_lower = [
        %HTML.Element{
          tag: "p",
          attrs: %{"style" => "text-transform: lowercase;"},
          children: [%HTML.Text{content: "HELLO"}]
        }
      ]

      assert [%Node{children: [%Text{content: "hello"}]}] = Cascade.build(dom_lower, [], [])
    end

    test "resolves units across rem, in, cm, mm, px" do
      dom = [
        %HTML.Element{
          tag: "div",
          attrs: %{
            "style" =>
              "margin-top: 1in; margin-right: 2.54cm; margin-bottom: 25.4mm; margin-left: 2rem;"
          },
          children: []
        }
      ]

      assert [%Node{computed: computed}] = Cascade.build(dom, [], [])
      assert computed.margin.top == 72.0
      assert_in_delta computed.margin.right, 72.0, 0.01
      assert_in_delta computed.margin.bottom, 72.0, 0.01
      assert computed.margin.left == 24.0
    end
  end
end
