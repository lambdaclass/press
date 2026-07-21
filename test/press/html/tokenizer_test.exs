defmodule Press.HTML.TokenizerTest do
  use ExUnit.Case, async: true

  alias Press.HTML.Tokenizer

  test "tokenizes plain text" do
    assert Tokenizer.tokenize("hello") == [{:text, "hello"}]
  end

  test "tokenizes a simple start and end tag" do
    assert Tokenizer.tokenize("<div>hi</div>") ==
             [{:start_tag, "div", %{}}, {:text, "hi"}, {:end_tag, "div"}]
  end

  test "lowercases tag and attribute names" do
    assert Tokenizer.tokenize(~s(<DIV CLASS="x"></DIV>)) ==
             [{:start_tag, "div", %{"class" => "x"}}, {:end_tag, "div"}]
  end

  test "parses double-quoted, single-quoted, and unquoted attribute values" do
    html = ~s(<input a="1" b='2' c=3>)

    assert Tokenizer.tokenize(html) ==
             [{:start_tag, "input", %{"a" => "1", "b" => "2", "c" => "3"}}]
  end

  test "accepts a bare attribute with no value" do
    assert Tokenizer.tokenize("<input disabled>") ==
             [{:start_tag, "input", %{"disabled" => ""}}]
  end

  test "first occurrence wins for duplicate attributes" do
    assert Tokenizer.tokenize(~s(<div class="a" class="b">)) ==
             [{:start_tag, "div", %{"class" => "a"}}]
  end

  test "ignores a trailing slash before > on any tag" do
    assert Tokenizer.tokenize("<br/>") == [{:start_tag, "br", %{}}]
    assert Tokenizer.tokenize("<div/>") == [{:start_tag, "div", %{}}]
  end

  test "unquoted attribute value stops at a trailing slash" do
    assert Tokenizer.tokenize("<input type=text/>") ==
             [{:start_tag, "input", %{"type" => "text"}}]
  end

  test "decodes minimal entities in text" do
    assert Tokenizer.tokenize("Ben &amp; Jerry&#39;s") == [{:text, "Ben & Jerry's"}]
  end

  test "leaves an unrecognized or malformed entity as literal text" do
    assert Tokenizer.tokenize("Ben & Jerry's") == [{:text, "Ben & Jerry's"}]
    assert Tokenizer.tokenize("A&ampB") == [{:text, "A&ampB"}]
  end

  test "decodes entities in attribute values" do
    assert Tokenizer.tokenize(~s(<a title="Ben &amp; Jerry's">)) ==
             [{:start_tag, "a", %{"title" => "Ben & Jerry's"}}]
  end

  test "discards comments" do
    assert Tokenizer.tokenize("a<!-- comment -->b") == [{:text, "ab"}]
  end

  test "treats a stray < that isn't a valid tag start as literal text" do
    assert Tokenizer.tokenize("1 < 2") == [{:text, "1 < 2"}]
  end

  test "drops an unterminated tag at end of input" do
    assert Tokenizer.tokenize(~s(text<div class="x)) == [{:text, "text"}]
  end

  test "captures <style> content as raw text, without decoding entities or matching tags inside it" do
    html = "<style>table > td { color: red; } /* a & b */</style>"

    assert Tokenizer.tokenize(html) ==
             [
               {:start_tag, "style", %{}},
               {:text, "table > td { color: red; } /* a & b */"},
               {:end_tag, "style"}
             ]
  end

  test "matches </style> case-insensitively" do
    assert Tokenizer.tokenize("<style>x</STYLE>") ==
             [{:start_tag, "style", %{}}, {:text, "x"}, {:end_tag, "style"}]
  end

  test "closes an unterminated <style> at end of input" do
    assert Tokenizer.tokenize("<style>a { color: red; }") ==
             [
               {:start_tag, "style", %{}},
               {:text, "a { color: red; }"},
               {:end_tag, "style"}
             ]
  end
end
