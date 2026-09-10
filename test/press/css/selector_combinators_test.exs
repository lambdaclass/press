defmodule Press.CSS.SelectorCombinatorsTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Selector
  alias Press.HTML.Element

  defp el(tag, attrs \\ %{}), do: %Element{tag: tag, attrs: attrs, children: []}

  # A path is the element plus its ancestors, nearest first; each entry carries
  # the element's position among its siblings so structural pseudo-classes and
  # the sibling combinators have something to work with.
  defp ctx(element, siblings, index), do: %{element: element, index: index, siblings: siblings}

  defp matches?(selector, path), do: Selector.matches?(Selector.parse(selector), path)

  describe "combinators" do
    test "the child combinator only matches the immediate parent" do
      parent = el("div", %{"class" => "box"})
      child = el("p")
      grandchild = el("span")

      direct = [ctx(child, [child], 0), ctx(parent, [parent], 0)]
      nested = [ctx(grandchild, [grandchild], 0), ctx(child, [child], 0), ctx(parent, [parent], 0)]

      assert matches?(".box > p", direct)
      refute matches?(".box > span", nested)
      assert matches?(".box span", nested)
    end

    test "the next-sibling combinator only matches the element right before" do
      a = el("h2")
      b = el("p")
      c = el("p")
      siblings = [a, b, c]

      assert matches?("h2 + p", [ctx(b, siblings, 1)])
      refute matches?("h2 + p", [ctx(c, siblings, 2)])
    end

    test "the subsequent-sibling combinator matches any earlier sibling" do
      a = el("h2")
      b = el("p")
      c = el("p")
      siblings = [a, b, c]

      assert matches?("h2 ~ p", [ctx(b, siblings, 1)])
      assert matches?("h2 ~ p", [ctx(c, siblings, 2)])
    end

    test "an unparseable fragment drops the whole selector" do
      assert Selector.parse("p[data-x=1]") == nil
    end

    test "the implicit descendant relation is not recorded on the compound" do
      assert Selector.parse(".a p") == [%{classes: ["a"]}, %{type: "p"}]
    end
  end

  describe "structural pseudo-classes" do
    test ":first-child and :last-child" do
      a = el("td")
      b = el("td")
      c = el("td")
      siblings = [a, b, c]

      assert matches?("td:first-child", [ctx(a, siblings, 0)])
      refute matches?("td:first-child", [ctx(b, siblings, 1)])
      assert matches?("td:last-child", [ctx(c, siblings, 2)])
      refute matches?("td:last-child", [ctx(b, siblings, 1)])
    end

    test ":nth-child with even, odd and a plain index" do
      rows = Enum.map(1..4, fn _ -> el("tr") end)
      [r1, r2, r3, _r4] = rows

      assert matches?("tr:nth-child(odd)", [ctx(r1, rows, 0)])
      assert matches?("tr:nth-child(even)", [ctx(r2, rows, 1)])
      refute matches?("tr:nth-child(even)", [ctx(r3, rows, 2)])
      assert matches?("tr:nth-child(3)", [ctx(r3, rows, 2)])
    end

    test ":first-of-type looks only at elements of the same tag" do
      h = el("h2")
      p1 = el("p")
      p2 = el("p")
      siblings = [h, p1, p2]

      assert matches?("p:first-of-type", [ctx(p1, siblings, 1)])
      refute matches?("p:first-of-type", [ctx(p2, siblings, 2)])
    end

    test ":root matches the document element" do
      html = el("html")
      body = el("body")

      assert matches?(":root", [ctx(html, [html], 0)])
      refute matches?(":root", [ctx(body, [body], 0)])
    end
  end

  describe "specificity" do
    test "a pseudo-class counts like a class" do
      {_, classes, _} = Selector.specificity(Selector.parse("td:first-child"))
      assert classes == 1
    end
  end
end
