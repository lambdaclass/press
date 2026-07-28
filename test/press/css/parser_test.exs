defmodule Press.CSS.ParserTest do
  use ExUnit.Case, async: true
  doctest Press.CSS.Parser

  alias Press.CSS.{PageRule, Parser, Rule}

  test "parses a simple rule" do
    {[], [rule]} = Parser.parse("h1 { color: red; }")

    assert %Rule{
             selector: [%{type: "h1"}],
             specificity: {0, 0, 1},
             declarations: %{"color" => {1.0, 0.0, 0.0}},
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

  test "expands a border shorthand" do
    {[], [rule]} = Parser.parse("div { border: 1px solid #000000; }")

    assert rule.declarations == %{
             "border-width" => {:length, 1.0, :px},
             "border-style" => :solid,
             "border-color" => {0.0, 0.0, 0.0}
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
end
