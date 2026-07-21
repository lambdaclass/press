# HTML Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Press.HTML.Parser`, a lenient HTML-string-to-DOM parser (Phase 2 of `press`) that never fails, so later phases (CSS cascade, layout) always have a tree to work with regardless of how imperfect the input markup is.

**Architecture:** Two stages, per the design doc: `Press.HTML.Tokenizer` (HTML string → token stream: start tags, end tags, text, with minimal entity decoding, comment discarding, and `<style>` raw-text mode) feeding `Press.HTML.TreeBuilder` (token stream → DOM, via a stack of open elements and 5 scoped auto-closing rules). `Press.HTML.Parser.parse/1` wires the two together as the public entry point. `Press.HTML.Entities` holds the shared entity-decoding helper used by both text and attribute values.

**Tech Stack:** Elixir, ExUnit. No runtime dependencies.

This is Phase 2 of the `press` HTML+CSS-to-PDF project. Read
`docs/superpowers/specs/2026-07-22-html-parser-design.md` (this plan's
spec) for full design rationale — tag list, entity scope, the 5
auto-closing rules, `<style>` raw-text handling, attribute parsing edge
cases. The general project spec is
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`. Phase 1
(`Press.PDF.*`, a separate, already-complete pipeline stage) is not
touched by this plan.

Per this project's documentation standard (README, moduledocs, and
doctests should be accurate and current, not bolted on later): the
public-facing module (`Press.HTML.Parser`) and the DOM structs
(`Press.HTML.Element`, `Press.HTML.Text`) get real `@moduledoc`/`@doc`
with a doctest. `Press.HTML.Tokenizer`, `Press.HTML.TreeBuilder`, and
`Press.HTML.Entities` are internal implementation stages (not part of
the public API), so they use `@moduledoc false`, matching the convention
already established for `Press.PDF.ContentStream`/`Writer` in Phase 1.

---

## Task 1: DOM structs

**Files:**
- Create: `lib/press/html/element.ex`
- Create: `lib/press/html/text.ex`

The two node types the parser produces and every later phase (Cascade,
Layout) consumes.

- [x] **Step 1: Write the implementation (no separate test — pure data, exercised by every later task's tests)**

```elixir
# lib/press/html/element.ex
defmodule Press.HTML.Element do
  @moduledoc """
  An HTML element node in the DOM produced by `Press.HTML.Parser`.

  `tag` and attribute names are always lowercase (see
  `Press.HTML.Parser` moduledoc). `attrs` maps attribute name to its
  (already entity-decoded) string value. `children` holds this
  element's child nodes in document order — a mix of `Press.HTML.Element`
  and `Press.HTML.Text`.
  """

  @type t :: %__MODULE__{
          tag: String.t(),
          attrs: %{String.t() => String.t()},
          children: [t() | Press.HTML.Text.t()]
        }

  defstruct tag: nil, attrs: %{}, children: []
end
```

```elixir
# lib/press/html/text.ex
defmodule Press.HTML.Text do
  @moduledoc """
  A text node in the DOM produced by `Press.HTML.Parser`.

  `content` has HTML entities already decoded (see `Press.HTML.Parser`
  moduledoc for the supported entity set).
  """

  @type t :: %__MODULE__{content: String.t()}

  defstruct content: ""
end
```

- [x] **Step 2: Compile and confirm no errors**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly, no warnings.

- [x] **Step 3: Commit**

```bash
git add lib/press/html/element.ex lib/press/html/text.ex
git commit -m "Add HTML DOM structs (Element, Text)"
```

---

## Task 2: Entity decoding

**Files:**
- Create: `lib/press/html/entities.ex`
- Test: `test/press/html/entities_test.exs`

Shared helper used by the Tokenizer for both text content and attribute
values. Scope per the design doc: the 5 XML entities + numeric entities
(decimal and hex); anything else (unrecognized name, missing `;`,
invalid digits) is left as literal text, unchanged.

- [x] **Step 1: Write the failing tests**

```elixir
defmodule Press.HTML.EntitiesTest do
  use ExUnit.Case, async: true

  alias Press.HTML.Entities

  test "decodes the 5 XML entities" do
    assert Entities.decode("&amp;") == "&"
    assert Entities.decode("&lt;") == "<"
    assert Entities.decode("&gt;") == ">"
    assert Entities.decode("&quot;") == "\""
    assert Entities.decode("&apos;") == "'"
  end

  test "decodes decimal numeric entities" do
    assert Entities.decode("&#233;") == "é"
  end

  test "decodes hex numeric entities, case-insensitively on the x" do
    assert Entities.decode("&#xE9;") == "é"
    assert Entities.decode("&#Xe9;") == "é"
  end

  test "decodes multiple entities in one string" do
    assert Entities.decode("Ben &amp; Jerry&#39;s") == "Ben & Jerry's"
  end

  test "leaves an unrecognized entity name as literal text" do
    assert Entities.decode("&nbsp;") == "&nbsp;"
  end

  test "leaves a malformed entity (no terminating ;) as literal text" do
    assert Entities.decode("&amp") == "&amp"
    assert Entities.decode("&#233") == "&#233"
  end

  test "leaves a bare & as literal text" do
    assert Entities.decode("Ben & Jerry's") == "Ben & Jerry's"
  end

  test "leaves text with no entities untouched" do
    assert Entities.decode("Hello world!") == "Hello world!"
  end
end
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/html/entities_test.exs`
Expected: FAIL — `Press.HTML.Entities` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.HTML.Entities do
  @moduledoc false

  @entity_regex ~r/&(amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9a-fA-F]+);/

  def decode(text) when is_binary(text) do
    Regex.replace(@entity_regex, text, &decode_match/2)
  end

  defp decode_match(_whole, "amp"), do: "&"
  defp decode_match(_whole, "lt"), do: "<"
  defp decode_match(_whole, "gt"), do: ">"
  defp decode_match(_whole, "quot"), do: "\""
  defp decode_match(_whole, "apos"), do: "'"

  defp decode_match(whole, "#" <> rest) do
    {digits, base} =
      case rest do
        "x" <> hex -> {hex, 16}
        "X" <> hex -> {hex, 16}
        dec -> {dec, 10}
      end

    case Integer.parse(digits, base) do
      {codepoint, ""} when codepoint in 0x00..0xD7FF or codepoint in 0xE000..0x10FFFF ->
        <<codepoint::utf8>>

      _ ->
        whole
    end
  end
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/html/entities_test.exs`
Expected: PASS (8 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/html/entities.ex test/press/html/entities_test.exs
git commit -m "Add minimal HTML entity decoding"
```

---

## Task 3: Tokenizer

**Files:**
- Create: `lib/press/html/tokenizer.ex`
- Test: `test/press/html/tokenizer_test.exs`

Turns an HTML string into a token list: `{:start_tag, tag, attrs}`,
`{:end_tag, tag}`, `{:text, content}`. Handles quoted/unquoted
attributes, comments, `<style>` raw-text mode, and case normalization.
Depends on `Press.HTML.Entities` (Task 2).

**Design notes not spelled out in the spec:**
- Content inside `<style>` is captured as *raw* text — entities are
  **not** decoded there (`&` in CSS content like `content: "A & B"`
  should pass through literally), matching how real browsers treat
  `<style>`/`<script>` as raw-text elements.
- Adjacent text runs must be merged into a single `{:text, _}` token.
  This matters whenever something in the middle gets discarded without
  emitting a token of its own — a comment (`a<!-- x -->b` is one run of
  text, `"ab"`, not two), or a stray `<` that isn't a valid tag start
  (`1 < 2` is one text token, not three). `emit_text/2` handles this by
  checking whether the token list already starts with a `{:text, _}`
  token and appending to it instead of always prepending a new one.

- [x] **Step 1: Write the failing tests**

```elixir
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/html/tokenizer_test.exs`
Expected: FAIL — `Press.HTML.Tokenizer` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.HTML.Tokenizer do
  @moduledoc false

  alias Press.HTML.Entities

  @style_close ~r/<\/style\s*>/i

  def tokenize(input) when is_binary(input) do
    input
    |> scan_text([])
    |> Enum.reverse()
  end

  # --- Text scanning: look for the next "<" ---

  defp scan_text(input, tokens) do
    case :binary.match(input, "<") do
      :nomatch ->
        emit_text(input, tokens)

      {pos, _len} ->
        text = binary_part(input, 0, pos)
        rest = binary_part(input, pos + 1, byte_size(input) - pos - 1)
        scan_tag_start(rest, emit_text(text, tokens))
    end
  end

  defp emit_text("", tokens), do: tokens

  defp emit_text(text, [{:text, prior} | rest]) do
    [{:text, prior <> Entities.decode(text)} | rest]
  end

  defp emit_text(text, tokens), do: [{:text, Entities.decode(text)} | tokens]

  defp emit_raw_text("", tokens), do: tokens
  defp emit_raw_text(text, tokens), do: [{:text, text} | tokens]

  # --- Right after "<": decide comment / end tag / start tag / literal ---

  defp scan_tag_start("!--" <> rest, tokens), do: skip_comment(rest, tokens)
  defp scan_tag_start("/" <> rest, tokens), do: scan_end_tag(rest, tokens)

  defp scan_tag_start(<<c, _::binary>> = rest, tokens) when c in ?a..?z or c in ?A..?Z do
    scan_start_tag(rest, tokens)
  end

  defp scan_tag_start(rest, tokens) do
    scan_text(rest, emit_text("<", tokens))
  end

  # --- Comments ---

  defp skip_comment(input, tokens) do
    case :binary.match(input, "-->") do
      :nomatch ->
        tokens

      {pos, _len} ->
        rest = binary_part(input, pos + 3, byte_size(input) - pos - 3)
        scan_text(rest, tokens)
    end
  end

  # --- End tags ---

  defp scan_end_tag(input, tokens) do
    case :binary.match(input, ">") do
      :nomatch ->
        tokens

      {pos, _len} ->
        tag = input |> binary_part(0, pos) |> String.trim() |> String.downcase()
        rest = binary_part(input, pos + 1, byte_size(input) - pos - 1)
        tokens = if tag == "", do: tokens, else: [{:end_tag, tag} | tokens]
        scan_text(rest, tokens)
    end
  end

  # --- Start tags ---

  defp scan_start_tag(input, tokens) do
    {tag, rest} = take_tag_name(input, "")
    {attrs, rest} = scan_attributes(rest, %{})

    case rest do
      "" -> tokens
      ">" <> rest -> emit_start_tag(tag, attrs, rest, tokens)
    end
  end

  defp take_tag_name(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?- do
    take_tag_name(rest, acc <> <<c>>)
  end

  defp take_tag_name(rest, acc), do: {String.downcase(acc), rest}

  defp emit_start_tag("style", attrs, rest, tokens) do
    tokens = [{:start_tag, "style", attrs} | tokens]

    case Regex.run(@style_close, rest, return: :index) do
      [{pos, len}] ->
        raw = binary_part(rest, 0, pos)
        after_close = binary_part(rest, pos + len, byte_size(rest) - pos - len)
        tokens = [{:end_tag, "style"} | emit_raw_text(raw, tokens)]
        scan_text(after_close, tokens)

      nil ->
        [{:end_tag, "style"} | emit_raw_text(rest, tokens)]
    end
  end

  defp emit_start_tag(tag, attrs, rest, tokens) do
    scan_text(rest, [{:start_tag, tag, attrs} | tokens])
  end

  # --- Attributes ---

  defp scan_attributes(input, attrs) do
    input = skip_whitespace(input)

    case input do
      "" -> {attrs, ""}
      ">" <> _ = rest -> {attrs, rest}
      "/" <> rest -> scan_attributes(rest, attrs)
      _ -> scan_attribute(input, attrs)
    end
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r] do
    skip_whitespace(rest)
  end

  defp skip_whitespace(rest), do: rest

  defp scan_attribute(input, attrs) do
    {name, rest} = take_attr_name(input, "")
    rest = skip_whitespace(rest)

    case rest do
      "=" <> rest ->
        rest = skip_whitespace(rest)
        {value, rest} = take_attr_value(rest)
        scan_attributes(rest, Map.put_new(attrs, name, value))

      _ ->
        scan_attributes(rest, Map.put_new(attrs, name, ""))
    end
  end

  defp take_attr_name(<<c, rest::binary>>, acc)
       when c not in [?\s, ?\t, ?\n, ?\r, ?=, ?/, ?>] do
    take_attr_name(rest, acc <> <<c>>)
  end

  defp take_attr_name(rest, acc), do: {String.downcase(acc), rest}

  defp take_attr_value(<<?", rest::binary>>), do: take_quoted(rest, ?", "")
  defp take_attr_value(<<?', rest::binary>>), do: take_quoted(rest, ?', "")
  defp take_attr_value(rest), do: take_unquoted(rest, "")

  defp take_quoted(<<c, rest::binary>>, c, acc), do: {Entities.decode(acc), rest}

  defp take_quoted(<<c, rest::binary>>, quote_char, acc) do
    take_quoted(rest, quote_char, acc <> <<c>>)
  end

  defp take_quoted("", _quote_char, acc), do: {Entities.decode(acc), ""}

  defp take_unquoted(<<c, rest::binary>>, acc)
       when c not in [?\s, ?\t, ?\n, ?\r, ?/, ?>] do
    take_unquoted(rest, acc <> <<c>>)
  end

  defp take_unquoted(rest, acc), do: {Entities.decode(acc), rest}
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/html/tokenizer_test.exs`
Expected: PASS (17 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/html/tokenizer.ex test/press/html/tokenizer_test.exs
git commit -m "Add HTML tokenizer"
```

---

## Task 4: TreeBuilder

**Files:**
- Create: `lib/press/html/tree_builder.ex`
- Test: `test/press/html/tree_builder_test.exs`

Consumes a token list (independent of the real Tokenizer — tests use
hand-built token lists) and builds the DOM via a stack of open elements,
applying the 5 auto-closing rules from the design doc.

- [x] **Step 1: Write the failing tests**

```elixir
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/html/tree_builder_test.exs`
Expected: FAIL — `Press.HTML.TreeBuilder` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.HTML.TreeBuilder do
  @moduledoc false

  alias Press.HTML.{Element, Text}

  @void_elements ~w(br img link meta)
  @p_closing_tags ~w(p div h1 h2 h3 h4 h5 h6 ul ol table header footer main)
  @sibling_closing_tags ~w(p li tr)
  @cell_tags ~w(td th)

  def build(tokens) do
    {stack, top_level} = Enum.reduce(tokens, {[], []}, &process_token/2)
    {[], top_level} = close_all({stack, top_level})
    Enum.reverse(top_level)
  end

  defp process_token({:text, ""}, state), do: state
  defp process_token({:text, content}, state), do: add_node(state, %Text{content: content})

  defp process_token({:start_tag, tag, attrs}, state) do
    state = autoclose(state, tag)

    if tag in @void_elements do
      add_node(state, %Element{tag: tag, attrs: attrs, children: []})
    else
      {stack, top_level} = state
      {[%{tag: tag, attrs: attrs, children: []} | stack], top_level}
    end
  end

  defp process_token({:end_tag, tag}, {stack, _top_level} = state) do
    if Enum.any?(stack, &(&1.tag == tag)) do
      close_until(state, tag)
    else
      state
    end
  end

  defp autoclose({[%{tag: top_tag} | _], _top_level} = state, new_tag) do
    cond do
      same_tag_sibling?(top_tag, new_tag) ->
        state |> close_top() |> autoclose(new_tag)

      top_tag in @cell_tags and new_tag == "tr" ->
        state |> close_top() |> autoclose(new_tag)

      top_tag == "p" and new_tag in @p_closing_tags ->
        state |> close_top() |> autoclose(new_tag)

      true ->
        state
    end
  end

  defp autoclose(state, _new_tag), do: state

  defp same_tag_sibling?(tag, tag) when tag in @sibling_closing_tags, do: true
  defp same_tag_sibling?(t1, t2) when t1 in @cell_tags and t2 in @cell_tags, do: true
  defp same_tag_sibling?(_t1, _t2), do: false

  defp close_until({[%{tag: tag} | _], _top_level} = state, tag), do: close_top(state)
  defp close_until(state, tag), do: state |> close_top() |> close_until(tag)

  defp close_all({[], top_level}), do: {[], top_level}
  defp close_all(state), do: state |> close_top() |> close_all()

  defp close_top({[frame | rest], top_level}) do
    element = %Element{tag: frame.tag, attrs: frame.attrs, children: Enum.reverse(frame.children)}
    add_node({rest, top_level}, element)
  end

  defp add_node({[frame | rest], top_level}, node) do
    {[%{frame | children: [node | frame.children]} | rest], top_level}
  end

  defp add_node({[], top_level}, node), do: {[], [node | top_level]}
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/html/tree_builder_test.exs`
Expected: PASS (11 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/html/tree_builder.ex test/press/html/tree_builder_test.exs
git commit -m "Add HTML tree builder with auto-closing rules"
```

---

## Task 5: Public Parser API

**Files:**
- Create: `lib/press/html/parser.ex`
- Test: `test/press/html/parser_test.exs`

Wires Tokenizer + TreeBuilder into the public entry point. This is the
module later phases (and external callers, eventually via `Press.render/2`)
will use — it gets real documentation and a doctest, per this project's
documentation standard.

- [x] **Step 1: Write the failing tests**

```elixir
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/html/parser_test.exs`
Expected: FAIL — `Press.HTML.Parser` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
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
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/html/parser_test.exs`
Expected: PASS (2 tests, 1 doctest, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/html/parser.ex test/press/html/parser_test.exs
git commit -m "Add Press.HTML.Parser public entry point"
```

---

## Task 6: End-to-end integration test

**Files:**
- Test: `test/press/html/integration_test.exs`

Realistic, slightly-imperfect HTML (mixed-case tags, unclosed `<li>`/
`<td>`/`<tr>`, a `<style>` block with `>` in a selector) through the
full `Press.HTML.Parser.parse/1` — confirms Tokenizer and TreeBuilder
work correctly together, not just in isolation. This is the acceptance
test for Phase 2.

- [x] **Step 1: Write the failing test**

```elixir
defmodule Press.HTML.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.HTML.{Element, Parser}

  test "parses a realistic, slightly-imperfect invoice-style fragment" do
    html = """
    <STYLE>table > td { border: 1px solid #000; }</STYLE>
    <div class="invoice">
      <h1>Invoice #123</h1>
      <ul>
        <li>Widget
        <li>Gadget
      </ul>
      <table>
        <tr><td>Widget<td>10.00
        <tr><td>Gadget<td>25.00
      </table>
    </div>
    """

    nodes = Parser.parse(html)

    assert [style] = find_all(nodes, "style")
    assert [text] = style.children
    assert text.content =~ "table > td"

    assert [invoice] = find_all(nodes, "div")
    assert invoice.attrs["class"] == "invoice"

    assert [h1] = find_all(invoice.children, "h1")
    assert [%{content: h1_text}] = h1.children
    assert h1_text =~ "Invoice #123"

    assert [ul] = find_all(invoice.children, "ul")
    assert length(find_all(ul.children, "li")) == 2

    assert [table] = find_all(invoice.children, "table")
    rows = find_all(table.children, "tr")
    assert length(rows) == 2
    assert Enum.all?(rows, fn row -> length(find_all(row.children, "td")) == 2 end)
  end

  defp find_all(nodes, tag) do
    Enum.filter(nodes, &match?(%Element{tag: ^tag}, &1))
  end
end
```

- [x] **Step 2: Run the test**

Run: `mix test test/press/html/integration_test.exs`
Expected: Given Tasks 1-5 are already implemented, this should PASS
immediately — it exercises only the already-built public API. If it
fails, that means an earlier task has a bug; fix the relevant module
(not this test) before continuing.

- [x] **Step 3: Run the full suite**

Run: `mix test`
Expected: All tests passing — Phase 1's ~32 tests plus Phase 2's new
ones, 0 failures.

- [x] **Step 4: Commit**

```bash
git add test/press/html/integration_test.exs
git commit -m "Add end-to-end integration test for HTML parser"
```

---

## Definition of Done

- [x] All tasks above complete, all tests passing (`mix test`).
- [x] `mix format --check-formatted` clean.
- [x] `docs/superpowers/plans/2026-07-22-html-parser.md` (this file) has every checkbox ticked.
- [ ] Next phase (Phase 3 — CSS parser + cascade, per
      `docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`) gets
      its own spec/plan when it's time to start it.
