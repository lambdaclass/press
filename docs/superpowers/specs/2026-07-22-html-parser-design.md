# Press Phase 2: HTML Parser — Design

Status: Approved for planning
Date: 2026-07-22

This is Phase 2 of the `press` project (see
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
overall architecture and roadmap). It implements the `Press.HTML.Parser`
stage: turning an HTML string into the DOM (`Press.HTML.Element`/
`Press.HTML.Text`) that Phase 3 (CSS cascade) will consume. It does not
touch CSS, layout, or PDF output.

## Scope

Tags supported (matches the general spec, with two additions found while
designing this parser): `html`, `head`, `style`, `body`, `div`, `span`,
`p`, `h1`–`h6`, `strong`/`b`, `em`/`i`, `br`, `ul`/`ol`/`li`, `table`/
`thead`/`tbody`/`tfoot`/`tr`/`th`/`td`, `img`, `header`, `footer`, `main`,
`link`, `meta`. Any other tag is treated as a generic, unknown block-level
element — not an error.

**Void elements** (no closing tag expected, ever — `<br>`, `<br/>`,
`<img src="...">`, `<link rel="stylesheet">`, `<meta charset="utf-8">`
are all valid as-is): `br`, `img`, `link`, `meta`.

**Entity decoding** (in both text content and attribute values): the 5
XML entities (`&amp; &lt; &gt; &quot; &apos;`) plus numeric entities
(`&#233;`, `&#xE9;`). Named HTML entities beyond those five (`&aacute;`,
`&euro;`, ...) are out of scope for Phase 2 — deferred in `TODO.md`,
since a caller can just write the UTF-8 character directly.

**Comments** (`<!-- ... -->`) are recognized and discarded — they never
appear in the token stream or the DOM.

**Case normalization:** tag and attribute names are lowercased during
tokenization (`<DIV CLASS="x">` behaves identically to `<div class="x">`),
matching browser behavior.

**Never fails:** like the rest of `press`, HTML parsing is best-effort.
Any input — however malformed — produces *some* DOM. There is no
`{:error, ...}` case for this stage (per the general spec's Errors
section).

## Architecture

Two stages, consistent with the rest of the project's preference for
small, independently-testable units over combined single-pass parsing:

```
HTML string ─▶ Press.HTML.Tokenizer ─▶ token stream
               (recognizes start/end tags, text, minimal entities;
                discards comments; switches to "raw text" mode inside
                <style> until it finds a literal </style>; lowercases
                tag/attribute names)

token stream ─▶ Press.HTML.TreeBuilder ─▶ DOM
                (stack of open elements, applies the auto-closing rules
                below, never fails)
```

**Tokens** (internal format, produced by the Tokenizer and consumed only
by the TreeBuilder — not part of any public API):

```elixir
{:start_tag, "div", %{"class" => "total"}, false}  # tag, attrs, self_closing?
{:end_tag, "div"}
{:text, "Hello world!"}
```

**DOM** (already defined in the general spec, reproduced here for
reference):

```elixir
%Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}, children: [...]}
%Press.HTML.Text{content: "Hello world!"}
```

## Auto-closing rules

Four concrete rules, scoped to the tags Phase 2 supports — not an attempt
to replicate full HTML5's much larger implicit-closing table:

1. **Same-tag sibling closing:** opening `p`, `li`, `tr`, `td`, or `th`
   while one of the same tag is already open (as the nearest "closable"
   ancestor) closes the previous one first. Handles `<li>one<li>two` and
   unclosed table rows/cells.
2. **Block tag inside `p`:** opening any block-level tag (`div`, `h1`–`h6`,
   `ul`, `ol`, `table`, `header`, `footer`, `main`, or another `p`) while
   a `p` is open closes that `p` first — a `<p>` can't contain a block.
3. **Mismatched end-tag recovery:** an end tag that doesn't match the top
   of the open-element stack searches up the stack for a matching open
   element. If found, everything down to and including it is closed
   (implicitly closing any unclosed descendants along the way). If not
   found anywhere in the stack, the stray end tag is ignored.
4. **End of input:** anything still open when the input ends is closed
   implicitly, innermost first.

## Attributes and `<style>` raw text

- **Attributes:** `name="value"`, `name='value'`, or `name=value`
  (unquoted, terminated by whitespace or `>`). A bare attribute with no
  value (`disabled`) is accepted with value `""`, though nothing in our
  current CSS property set uses boolean attributes.
- **`<style>` as raw text:** the tokenizer enters "raw text mode" as soon
  as it sees `<style...>` and stops interpreting `<`/`>` as markup until
  it finds a literal `</style>` — so CSS content containing things like
  `table > td` isn't mistaken for HTML tags.

## Testing

- **Tokenizer unit tests:** HTML fragments → expected token list
  (start/end tags, text with entities decoded, `<style>` raw-text mode,
  void elements never producing an end tag, comments discarded).
- **TreeBuilder unit tests:** hand-built token lists (bypassing the real
  tokenizer) → expected DOM tree, with each of the 4 auto-closing rules
  covered by its own test.
- **Full-parser integration tests:** realistic, slightly-imperfect HTML
  (unclosed `<li>`/`<td>`, mixed-case tags, a `<style>` block with `>` in
  a selector) → final DOM, confirming both stages work correctly together.
