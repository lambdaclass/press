defmodule Press.HTML.ParserTest do
  use ExUnit.Case, async: true
  doctest Press.HTML.Parser

  alias Press.HTML.{Element, Parser, Text}

  test "parses a bare fragment into a list of top-level nodes, no implicit wrapping" do
    assert Parser.parse("<h1>Hello world!</h1>") == [
             %Element{tag: "h1", attrs: %{}, children: [%Text{content: "Hello world!"}]}
           ]
  end

  test "parses multiple top-level siblings" do
    assert Parser.parse("<p>a</p><p>b</p>") == [
             %Element{tag: "p", attrs: %{}, children: [%Text{content: "a"}]},
             %Element{tag: "p", attrs: %{}, children: [%Text{content: "b"}]}
           ]
  end
end
