defmodule Press.CSS.SelectorTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Selector

  describe "parse/1" do
    test "parses a bare type selector" do
      assert Selector.parse("div") == [%{type: "div"}]
    end

    test "parses a bare class selector" do
      assert Selector.parse(".total") == [%{classes: ["total"]}]
    end

    test "parses a bare id selector" do
      assert Selector.parse("#header") == [%{id: "header"}]
    end

    test "parses a compound selector" do
      assert Selector.parse("div.total#x") == [%{type: "div", classes: ["total"], id: "x"}]
    end

    test "parses a descendant chain" do
      assert Selector.parse("table td.total") ==
               [%{type: "table"}, %{type: "td", classes: ["total"]}]
    end

    test "parses multiple classes chained on one compound" do
      assert Selector.parse(".foo.bar") == [%{classes: ["foo", "bar"]}]
    end
  end

  describe "specificity/1" do
    test "counts ids, classes, and types across all compound steps" do
      assert Selector.specificity([%{type: "table"}, %{type: "td", classes: ["total"]}]) ==
               {0, 1, 2}

      assert Selector.specificity([%{id: "x"}]) == {1, 0, 0}
      assert Selector.specificity([%{type: "div"}]) == {0, 0, 1}
    end

    test "counts each chained class separately" do
      assert Selector.specificity([%{classes: ["foo", "bar"]}]) == {0, 2, 0}
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
      assert Selector.matches?([%{classes: ["total"]}], element, [])
      refute Selector.matches?([%{classes: ["missing"]}], element, [])
    end

    test "a chained multi-class selector requires every class to be present" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "btn btn-primary"}}
      assert Selector.matches?([%{classes: ["btn", "btn-primary"]}], element, [])
      refute Selector.matches?([%{classes: ["btn", "btn-secondary"]}], element, [])
    end

    test "id matching is exact" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"id" => "header"}}
      assert Selector.matches?([%{id: "header"}], element, [])
    end

    test "a compound selector requires every part to hold" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}}
      assert Selector.matches?([%{type: "div", classes: ["total"]}], element, [])
      refute Selector.matches?([%{type: "span", classes: ["total"]}], element, [])
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

    test "universal selector matches any element" do
      element = %Press.HTML.Element{tag: "div", attrs: %{}}
      assert Selector.matches?([%{universal: true}], element, [])
      assert Selector.parse("*") == [%{universal: true}]
    end

    test "strips pseudo-elements and ignores interactive pseudo-classes" do
      assert Selector.parse("div::before") == [%{type: "div"}]
      assert Selector.parse("button:hover") == nil
      assert Selector.parse("a:focus") == nil
    end
  end
end
