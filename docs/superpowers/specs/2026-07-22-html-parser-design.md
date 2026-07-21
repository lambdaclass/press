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
element — not an error. This includes `<script>`: it isn't part of
`press`'s scope (there's no JavaScript execution or special handling),
so it gets no `<style>`-like raw-text treatment and its content is parsed
as ordinary markup. Any resulting odd tokenization from real script
content (which often contains `<`/`>`) is acceptable — scripts aren't a
supported input for this library.

**Void elements** (no closing tag expected, ever — `<br>`, `<br/>`,
`<img src="...">`, `<link rel="stylesheet">`, `<meta charset="utf-8">`
are all valid as-is): `br`, `img`, `link`, `meta`.

**Entity decoding** (in both text content and attribute values): the 5
XML entities (`&amp; &lt; &gt; &quot; &apos;`) plus numeric entities
(`&#233;`, `&#xE9;`). Named HTML entities beyond those five (`&aacute;`,
`&euro;`, ...) are out of scope for Phase 2 — deferred in `TODO.md`,
since a caller can just write the UTF-8 character directly. A `&` that
isn't the start of one of these recognized forms (e.g. `Ben & Jerry's`)
is left as a literal `&` in the output, matching browser behavior —
never an error, never dropped. The same applies to a malformed or
incomplete match of a recognized form — a missing terminating `;`
(`&amp`, `&#233`) or invalid digits (`&#xZZ;`) — the whole thing is left
as literal text starting from the `&`, exactly as if it weren't
recognized at all.

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
{:start_tag, "div", %{"class" => "total"}}  # tag, attrs
{:end_tag, "div"}
{:text, "Hello world!"}
```

A trailing `/` before `>` (`<div/>`, `<br/>`) is recognized by the
tokenizer but carries no separate signal in the token — it doesn't
change how the TreeBuilder treats the tag. Void-ness is determined purely
by tag name (see "Void elements" above): void tags never expect a closing
tag or children regardless of whether they're written with a trailing
slash; non-void tags are never self-closed by a trailing slash, matching
real HTML5 behavior where a stray `/>` on an ordinary element is ignored
(`<div/>foo</div>` still parses `foo` as a child of `div`).

**DOM** (already defined in the general spec, reproduced here for
reference):

```elixir
%Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}, children: [...]}
%Press.HTML.Text{content: "Hello world!"}
```

## Public API and parse result

```elixir
Press.HTML.Parser.parse(html) :: [Press.HTML.Element.t() | Press.HTML.Text.t()]
```

Phase 2 does **not** implement implicit `<html>`/`<head>`/`<body>`
insertion the way a full browser parser does. It parses exactly the
elements present in the input and returns the resulting list of
top-level sibling nodes. For the common case — a bare fragment with no
wrapping tag at all, e.g. `html = "<h1>Hello world!</h1>"` from the
general spec's usage example — the result is a one-or-more-element list
of siblings, not a single required root. If the input does contain a
literal `<html>...</html>`, that's simply the (single) top-level element
in the returned list; no special handling beyond ordinary parsing. Later
phases (Cascade, Layout) consume this list directly as the top-level
children of an implicit document root — they don't need an actual
`Press.HTML.Element{tag: "html", ...}` wrapper to exist in the data.

## Auto-closing rules

Five concrete rules, scoped to the tags Phase 2 supports — not an attempt
to replicate full HTML5's much larger implicit-closing table:

1. **Same-tag sibling closing:** opening `p`, `li`, `tr`, `td`, or `th`
   while one of the same tag is already open (as the nearest "closable"
   ancestor) closes the previous one first. Handles `<li>one<li>two` and
   unclosed table cells (`<td>a<td>b`).
2. **`tr` closes a dangling cell:** opening `tr` while a `td` or `th` is
   still open closes that cell first (in addition to closing a previous
   `tr`, already covered by rule 1) — so `<tr><td>a<td>b<tr><td>c` closes
   both the second `<td>` and the first `<tr>` when the second `<tr>`
   opens, rather than nesting the new row inside the dangling cell.
3. **Block tag inside `p`:** opening any block-level tag (`div`, `h1`–`h6`,
   `ul`, `ol`, `table`, `header`, `footer`, `main`, or another `p`) while
   a `p` is open closes that `p` first — a `<p>` can't contain a block.
4. **Mismatched end-tag recovery:** an end tag that doesn't match the top
   of the open-element stack searches up the stack for a matching open
   element. If found, everything down to and including it is closed
   (implicitly closing any unclosed descendants along the way). If not
   found anywhere in the stack, the stray end tag is ignored.
5. **End of input:** anything still open when the input ends is closed
   implicitly, innermost first.

## Attributes and `<style>` raw text

- **Attributes:** `name="value"`, `name='value'`, or `name=value`
  (unquoted, terminated by whitespace, `/`, or `>` — so
  `<input type=text/>` reads the unquoted value as `text`, not `text/`).
  A bare attribute with no
  value (`disabled`) is accepted with value `""`, though nothing in our
  current CSS property set uses boolean attributes. If the same attribute
  name appears more than once on a tag (`<div class="a" class="b">`), the
  first occurrence wins and later duplicates are ignored, matching HTML5
  parsing behavior.
- **`<style>` as raw text:** the tokenizer enters "raw text mode" as soon
  as it sees `<style...>` and stops interpreting `<`/`>` as markup until
  it finds a literal `</style>` — so CSS content containing things like
  `table > td` isn't mistaken for HTML tags. If the input ends before a
  literal `</style>` is found, everything from `<style...>` to the end of
  input becomes that element's text content (the same "end of input
  closes what's still open" behavior as auto-closing rule 4) — never an
  infinite scan or an error.

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
