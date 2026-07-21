defmodule Press.HTML.TreeBuilderTest do
  use ExUnit.Case, async: true

  alias Press.HTML.{Element, Text, TreeBuilder}

  test "builds a single element with text content" do
    tokens = [{:start_tag, "div", %{}}, {:text, "hi"}, {:end_tag, "div"}]

    assert TreeBuilder.build(tokens) == [
             %Element{tag: "div", attrs: %{}, children: [%Text{content: "hi"}]}
           ]
  end

  test "returns multiple top-level sibling nodes for a bare fragment" do
    tokens = [{:start_tag, "h1", %{}}, {:text, "Hello"}, {:end_tag, "h1"}, {:text, "!"}]

    assert TreeBuilder.build(tokens) == [
             %Element{tag: "h1", attrs: %{}, children: [%Text{content: "Hello"}]},
             %Text{content: "!"}
           ]
  end

  test "does not push void elements onto the stack" do
    tokens = [{:start_tag, "p", %{}}, {:start_tag, "br", %{}}, {:text, "x"}, {:end_tag, "p"}]

    assert TreeBuilder.build(tokens) == [
             %Element{
               tag: "p",
               attrs: %{},
               children: [%Element{tag: "br", attrs: %{}, children: []}, %Text{content: "x"}]
             }
           ]
  end

  test "rule 1: same-tag sibling closing for li" do
    tokens = [
      {:start_tag, "li", %{}},
      {:text, "one"},
      {:start_tag, "li", %{}},
      {:text, "two"},
      {:end_tag, "li"}
    ]

    assert TreeBuilder.build(tokens) == [
             %Element{tag: "li", attrs: %{}, children: [%Text{content: "one"}]},
             %Element{tag: "li", attrs: %{}, children: [%Text{content: "two"}]}
           ]
  end

  test "rule 1: td and th close each other" do
    tokens = [
      {:start_tag, "tr", %{}},
      {:start_tag, "td", %{}},
      {:text, "a"},
      {:start_tag, "th", %{}},
      {:text, "b"},
      {:end_tag, "tr"}
    ]

    assert TreeBuilder.build(tokens) == [
             %Element{
               tag: "tr",
               attrs: %{},
               children: [
                 %Element{tag: "td", attrs: %{}, children: [%Text{content: "a"}]},
                 %Element{tag: "th", attrs: %{}, children: [%Text{content: "b"}]}
               ]
             }
           ]
  end

  test "rule 2: tr closes a dangling td when the next tr opens" do
    tokens = [
      {:start_tag, "tr", %{}},
      {:start_tag, "td", %{}},
      {:text, "a"},
      {:start_tag, "td", %{}},
      {:text, "b"},
      {:start_tag, "tr", %{}},
      {:start_tag, "td", %{}},
      {:text, "c"}
    ]

    assert TreeBuilder.build(tokens) == [
             %Element{
               tag: "tr",
               attrs: %{},
               children: [
                 %Element{tag: "td", attrs: %{}, children: [%Text{content: "a"}]},
                 %Element{tag: "td", attrs: %{}, children: [%Text{content: "b"}]}
               ]
             },
             %Element{
               tag: "tr",
               attrs: %{},
               children: [%Element{tag: "td", attrs: %{}, children: [%Text{content: "c"}]}]
             }
           ]
  end

  test "rule 3: a block tag closes an open p" do
    tokens = [
      {:start_tag, "p", %{}},
      {:text, "hello"},
      {:start_tag, "div", %{}},
      {:text, "world"},
      {:end_tag, "div"}
    ]

    assert TreeBuilder.build(tokens) == [
             %Element{tag: "p", attrs: %{}, children: [%Text{content: "hello"}]},
             %Element{tag: "div", attrs: %{}, children: [%Text{content: "world"}]}
           ]
  end

  test "rule 4: a mismatched end tag closes back to the matching ancestor" do
    tokens = [
      {:start_tag, "div", %{}},
      {:start_tag, "span", %{}},
      {:text, "x"},
      {:end_tag, "div"}
    ]

    assert TreeBuilder.build(tokens) == [
             %Element{
               tag: "div",
               attrs: %{},
               children: [%Element{tag: "span", attrs: %{}, children: [%Text{content: "x"}]}]
             }
           ]
  end

  test "rule 4: a stray end tag with no matching open element is ignored" do
    tokens = [{:start_tag, "div", %{}}, {:text, "x"}, {:end_tag, "span"}, {:end_tag, "div"}]

    assert TreeBuilder.build(tokens) == [
             %Element{tag: "div", attrs: %{}, children: [%Text{content: "x"}]}
           ]
  end

  test "rule 5: unclosed elements are closed at end of input" do
    tokens = [{:start_tag, "div", %{}}, {:start_tag, "span", %{}}, {:text, "x"}]

    assert TreeBuilder.build(tokens) == [
             %Element{
               tag: "div",
               attrs: %{},
               children: [%Element{tag: "span", attrs: %{}, children: [%Text{content: "x"}]}]
             }
           ]
  end

  test "a text token with empty content produces no node" do
    tokens = [{:start_tag, "div", %{}}, {:text, ""}, {:end_tag, "div"}]

    assert TreeBuilder.build(tokens) == [%Element{tag: "div", attrs: %{}, children: []}]
  end
end
