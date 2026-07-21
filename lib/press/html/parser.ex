defmodule Press.HTML.Parser do
  @moduledoc """
  Parses an HTML string into a list of top-level DOM nodes
  (`Press.HTML.Element` / `Press.HTML.Text`).

  The parser is deliberately lenient and never raises: malformed or
  incomplete markup still produces *some* result, the same way a
  browser never refuses to render a page over bad HTML. See
  `docs/superpowers/specs/2026-07-22-html-parser-design.md` for the
  full design — supported tags, entity decoding scope, and the 5
  auto-closing rules used to recover from unclosed tags.
  """

  alias Press.HTML.{Element, Text, Tokenizer, TreeBuilder}

  @doc """
  Parses `html` into a list of top-level nodes.

  There is no implicit `<html>`/`<head>`/`<body>` insertion: a bare
  fragment like `"<h1>Hello world!</h1>"` returns a list with that one
  element in it, not a document wrapped in extra structure.

  ## Examples

      iex> Press.HTML.Parser.parse("<h1>Hello world!</h1>")
      [%Press.HTML.Element{tag: "h1", attrs: %{}, children: [%Press.HTML.Text{content: "Hello world!"}]}]

  """
  @spec parse(String.t()) :: [Element.t() | Text.t()]
  def parse(html) when is_binary(html) do
    html
    |> Tokenizer.tokenize()
    |> TreeBuilder.build()
  end
end
