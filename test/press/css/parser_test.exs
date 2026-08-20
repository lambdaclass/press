defmodule Press.CSS.ParserTest do
  use ExUnit.Case, async: true
  doctest Press.CSS.Parser

  alias Press.CSS.{PageRule, Parser, Rule}

  test "parses a simple rule" do
    {[], [rule]} = Parser.parse("h1 { color: red; }")

    assert %Rule{
             selector: [%{type: "h1"}],
             specificity: {0, 0, 1},
             declarations: %{"color" => {1.0, +0.0, +0.0}},
             source_index: 0
           } = rule
  end

  test "computes specificity for a compound descendant selector" do
    {[], [rule]} = Parser.parse("table td.total { color: red; }")
    assert rule.specificity == {0, 1, 2}
  end

  test "expands comma-grouped selectors into separate rules sharing source_index" do
    {[], [r1, r2]} = Parser.parse("h1, h2 { color: red; }")
    assert r1.selector == [%{type: "h1"}]
    assert r2.selector == [%{type: "h2"}]
    assert r1.source_index == 0
    assert r2.source_index == 0
  end

  test "increments source_index across separate rule blocks" do
    {[], [r1, r2]} = Parser.parse("h1 { color: red; } h2 { color: blue; }")
    assert r1.source_index == 0
    assert r2.source_index == 1
  end

  test "expands a margin shorthand into longhand declarations" do
    {[], [rule]} = Parser.parse("p { margin: 1em 0; }")

    assert rule.declarations == %{
             "margin-top" => {:length, 1.0, :em},
             "margin-right" => {:length, 0, :pt},
             "margin-bottom" => {:length, 1.0, :em},
             "margin-left" => {:length, 0, :pt}
           }
  end

  test "expands a border shorthand to all four sides" do
    {[], [rule]} = Parser.parse("div { border: 1px solid #000000; }")

    assert rule.declarations == %{
             "border-width-top" => {:length, 1.0, :px},
             "border-width-right" => {:length, 1.0, :px},
             "border-width-bottom" => {:length, 1.0, :px},
             "border-width-left" => {:length, 1.0, :px},
             "border-style-top" => :solid,
             "border-style-right" => :solid,
             "border-style-bottom" => :solid,
             "border-style-left" => :solid,
             "border-color-top" => {0.0, 0.0, 0.0},
             "border-color-right" => {0.0, 0.0, 0.0},
             "border-color-bottom" => {0.0, 0.0, 0.0},
             "border-color-left" => {0.0, 0.0, 0.0}
           }
  end

  test "parses line-height's unitless multiplier" do
    {[], [rule]} = Parser.parse("p { line-height: 1.5; }")
    assert rule.declarations == %{"line-height" => {:line_height, :multiplier, 1.5}}
  end

  test "maps common font-family aliases and falls back to helvetica for unknown names" do
    {[], [r1]} = Parser.parse("p { font-family: Arial; }")
    {[], [r2]} = Parser.parse("p { font-family: \"Comic Sans MS\"; }")
    assert r1.declarations == %{"font-family" => :helvetica}
    assert r2.declarations == %{"font-family" => :helvetica}
  end

  test "skips a malformed declaration but keeps the rest of the rule" do
    {[], [rule]} = Parser.parse("p { color: red; nonsense-here; font-weight: bold; }")
    assert rule.declarations == %{"color" => {1.0, 0.0, 0.0}, "font-weight" => :bold}
  end

  test "drops an unrecognized property/value silently" do
    {[], [rule]} = Parser.parse("p { color: red; border-style: dashed; }")
    assert rule.declarations == %{"color" => {1.0, 0.0, 0.0}}
  end

  test "drops a rule with no closing brace" do
    assert Parser.parse("h1 { color: red;") == {[], []}
  end

  test "strips comments before parsing" do
    {[], [rule]} = Parser.parse("/* note */ h1 { color: red; /* inline */ }")
    assert rule.declarations == %{"color" => {1.0, 0.0, 0.0}}
  end

  test "parses an @page rule with size and margin" do
    {[page], []} = Parser.parse("@page { size: A4; margin: 20mm 15mm 25mm 15mm; }")

    assert %PageRule{
             declarations: %{
               "size" => :a4,
               "margin" => %{
                 top: {:length, 20.0, :mm},
                 right: {:length, 15.0, :mm},
                 bottom: {:length, 25.0, :mm},
                 left: {:length, 15.0, :mm}
               }
             },
             source_index: 0
           } = page
  end

  test "parses a custom @page size" do
    {[page], []} = Parser.parse("@page { size: 210mm 297mm; }")

    assert page.declarations == %{
             "size" => {:custom, {:length, 210.0, :mm}, {:length, 297.0, :mm}}
           }
  end

  test "parses keyword properties and side-specific properties" do
    css = """
    p {
      text-align: center;
      vertical-align: middle;
      text-transform: uppercase;
      list-style-type: disc;
      box-sizing: border-box;
      border-collapse: collapse;
      page-break-before: always;
      padding-top: 5px;
      padding-left: 10px;
      margin-bottom: 12pt;
      border-bottom: 2px solid blue;
    }
    """

    {[], [rule]} = Parser.parse(css)

    assert rule.declarations["text-align"] == :center
    assert rule.declarations["vertical-align"] == :middle
    assert rule.declarations["text-transform"] == :uppercase
    assert rule.declarations["box-sizing"] == :"border-box"
    assert rule.declarations["border-collapse"] == :collapse
    assert rule.declarations["page-break-before"] == :always
    assert rule.declarations["padding-top"] == {:length, 5.0, :px}
    assert rule.declarations["padding-left"] == {:length, 10.0, :px}
    assert rule.declarations["margin-bottom"] == {:length, 12.0, :pt}
  end

  test "parses font aliases for times and courier" do
    {[], [r1]} = Parser.parse("p { font-family: 'Times New Roman'; }")
    {[], [r2]} = Parser.parse("code { font-family: monospace; }")
    assert r1.declarations["font-family"] == :times
    assert r2.declarations["font-family"] == :courier
  end

  test "parses rules inside @media blocks" do
    css = """
    @media print {
      h1 { color: black; }
    }
    """

    {[], [rule]} = Parser.parse(css)
    assert rule.declarations["color"] == {0.0, 0.0, 0.0}
  end

  test "resolves tailwind CSS variables and calc expressions" do
    css = """
    .card {
      font-size: var(--text-xs);
      font-weight: var(--font-weight-semibold);
      font-family: var(--font-mono);
      padding: calc(var(--spacing) * 4);
      margin-inline: 1rem;
      margin-block: 0.5rem;
      border-top: 1px solid #111;
      border-left: 2px solid #222;
      border-style: solid;
    }
    """

    {[], [rule]} = Parser.parse(css)
    assert rule.declarations["font-size"] == {:length, 0.75, :rem}
    assert rule.declarations["font-weight"] == :bold
    assert rule.declarations["font-family"] == :courier
    assert rule.declarations["padding-top"] == {:length, 1.0, :rem}
    assert rule.declarations["margin-left"] == {:length, 1.0, :rem}
    assert rule.declarations["margin-right"] == {:length, 1.0, :rem}
    assert rule.declarations["margin-top"] == {:length, 0.5, :rem}
    assert rule.declarations["border-width-top"] == {:length, 1.0, :px}
    assert rule.declarations["border-width-left"] == {:length, 2.0, :px}
  end

  test "expands :where() and :is() functional pseudo-classes" do
    css = """
    .table-xs :where(th, td) {
      padding-inline: 8px;
    }
    """

    {[], [r1, r2]} = Parser.parse(css)
    assert r1.selector == [%{classes: ["table-xs"]}, %{type: "th"}]
    assert r2.selector == [%{classes: ["table-xs"]}, %{type: "td"}]
    assert r1.declarations["padding-left"] == {:length, 8.0, :px}
    assert r2.declarations["padding-right"] == {:length, 8.0, :px}
  end

  test "flattens nested CSS rules and @layer blocks (daisyUI 5 / Tailwind v4 pattern)" do
    css = """
    .table-xs {
      @layer daisyui.l1.l2 {
        :where(th, td) {
          padding-inline: calc(0.25rem * 2);
          padding-block: calc(0.25rem * 1);
        }
      }
    }
    """

    {[], [r1, r2]} = Parser.parse(css)
    assert r1.selector == [%{classes: ["table-xs"]}, %{type: "th"}]
    assert r2.selector == [%{classes: ["table-xs"]}, %{type: "td"}]
    assert r1.declarations["padding-left"] == {:length, 0.5, :rem}
    assert r1.declarations["padding-right"] == {:length, 0.5, :rem}
    assert r1.declarations["padding-top"] == {:length, 0.25, :rem}
    assert r1.declarations["padding-bottom"] == {:length, 0.25, :rem}
  end

  test "parses logical directional properties (start and end)" do
    css = """
    div {
      padding-inline-start: 10px;
      padding-inline-end: 20px;
      padding-block-start: 5px;
      padding-block-end: 15px;
      margin-inline-start: 2px;
      margin-inline-end: 4px;
      margin-block-start: 6px;
      margin-block-end: 8px;
    }
    """

    {[], [rule]} = Parser.parse(css)
    assert rule.declarations["padding-left"] == {:length, 10.0, :px}
    assert rule.declarations["padding-right"] == {:length, 20.0, :px}
    assert rule.declarations["padding-top"] == {:length, 5.0, :px}
    assert rule.declarations["padding-bottom"] == {:length, 15.0, :px}
    assert rule.declarations["margin-left"] == {:length, 2.0, :px}
    assert rule.declarations["margin-right"] == {:length, 4.0, :px}
    assert rule.declarations["margin-top"] == {:length, 6.0, :px}
    assert rule.declarations["margin-bottom"] == {:length, 8.0, :px}
  end
end
