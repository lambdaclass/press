defmodule Press.CSS.SelectorTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Selector

  describe "parse/1" do
    test "parses a bare type selector" do
      assert Selector.parse("div") == [%{type: "div"}]
    end

    test "parses a bare class selector" do
      assert Selector.parse(".total") == [%{class: "total"}]
    end

    test "parses a bare id selector" do
      assert Selector.parse("#header") == [%{id: "header"}]
    end

    test "parses a compound selector" do
      assert Selector.parse("div.total#x") == [%{type: "div", class: "total", id: "x"}]
    end

    test "parses a descendant chain" do
      assert Selector.parse("table td.total") == [%{type: "table"}, %{type: "td", class: "total"}]
    end
  end

  describe "specificity/1" do
    test "counts ids, classes, and types across all compound steps" do
      assert Selector.specificity([%{type: "table"}, %{type: "td", class: "total"}]) == {0, 1, 2}
      assert Selector.specificity([%{id: "x"}]) == {1, 0, 0}
      assert Selector.specificity([%{type: "div"}]) == {0, 0, 1}
    end
  end

  describe "matches?/3" do
    test "a bare type selector matches the element itself" do
      element = %Press.HTML.Element{tag: "div", attrs: %{}}
      assert Selector.matches?([%{type: "div"}], element, [])
      refute Selector.matches?([%{type: "span"}], element, [])
    end

    test "class matching is token-based" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "foo total bar"}}
      assert Selector.matches?([%{class: "total"}], element, [])
      refute Selector.matches?([%{class: "missing"}], element, [])
    end

    test "id matching is exact" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"id" => "header"}}
      assert Selector.matches?([%{id: "header"}], element, [])
    end

    test "a compound selector requires every part to hold" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}}
      assert Selector.matches?([%{type: "div", class: "total"}], element, [])
      refute Selector.matches?([%{type: "span", class: "total"}], element, [])
    end

    test "a descendant combinator matches an ancestor at any depth, not just the immediate parent" do
      element = %Press.HTML.Element{tag: "td", attrs: %{}}
      grandparent = %Press.HTML.Element{tag: "table", attrs: %{}}
      parent = %Press.HTML.Element{tag: "tr", attrs: %{}}

      assert Selector.matches?([%{type: "table"}, %{type: "td"}], element, [parent, grandparent])
    end

    test "a descendant combinator fails if no ancestor matches" do
      element = %Press.HTML.Element{tag: "td", attrs: %{}}
      parent = %Press.HTML.Element{tag: "tr", attrs: %{}}

      refute Selector.matches?([%{type: "table"}, %{type: "td"}], element, [parent])
    end

    test "the last selector step must match the element, not an ancestor" do
      element = %Press.HTML.Element{tag: "tr", attrs: %{}}
      grandparent = %Press.HTML.Element{tag: "table", attrs: %{}}

      refute Selector.matches?([%{type: "table"}, %{type: "td"}], element, [grandparent])
    end
  end
end
