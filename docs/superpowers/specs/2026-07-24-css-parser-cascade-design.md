# Press Phase 3: CSS Parser + Cascade — Design

Status: Approved for planning
Date: 2026-07-24

This is Phase 3 of the `press` project (see
`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md` for the
overall architecture and roadmap). It implements two pipeline stages:
`Press.CSS.Parser` (CSS string → rule list) and `Press.Style.Cascade`
(DOM + rules → styled tree). Phase 2's HTML parser
(`docs/superpowers/specs/2026-07-22-html-parser-design.md`) is a
dependency (Cascade walks the DOM it produces) but is not modified here.
Layout (Phase 4) is not touched by this plan.

## Correction to the general spec: percentages resolve at layout time, not cascade time

The general spec (2026-07-20) states units including `%` are "resolved
to points during the cascade stage." This is only true for absolute
units, `em`, and `rem` — all three depend only on font-size, which is a
purely stylistic concept the cascade can resolve on its own. `%`
depends on the *containing block's width*, which is a layout concept:
the cascade stage has no box positions or widths to measure against.

**Resolution:** the cascade resolves absolute units, `em`, and `rem` to
points. `%` values are left symbolic — `{:percent, 50.0}` instead of a
point value — for Phase 4 (Layout) to resolve once it knows the actual
containing block width. This matches how browsers work (percentage
lengths are a layout-time concept, not a style-time one) and avoids
having to redo this boundary later.

## Data model

```elixir
# Press.CSS.Rule (style_rules) — declaration values are already parsed into
# typed-but-context-free terms (see "Value parsing" below), not raw strings
%Press.CSS.Rule{
  selector: [%{type: "table"}, %{type: "td", classes: ["total"]}],
  specificity: {0, 1, 2},   # {ids, classes, types}
  declarations: %{"color" => {1.0, 0.0, 0.0}, "font-size" => {:length, 12, :px}},
  source_index: 3           # position among rules of the same parse call, for tie-breaking
}

# Press.CSS.PageRule (page_rules) — unlike Press.CSS.Rule, box-shorthand
# expansion produces one already-structured value per property, not
# separate longhand keys (see "@page parsing" below for why)
%Press.CSS.PageRule{
  declarations: %{
    "size" => :a4,
    "margin" => %{
      top: {:length, 20, :mm},
      right: {:length, 20, :mm},
      bottom: {:length, 20, :mm},
      left: {:length, 20, :mm}
    }
  },
  source_index: 0
}

# Press.CSS.Parser.parse/1 result
{page_rules :: [Press.CSS.PageRule.t()], style_rules :: [Press.CSS.Rule.t()]}
```

`Press.CSS.Rule`/`Press.CSS.PageRule` intentionally have no `origin`
field — `Press.CSS.Parser` is a pure syntax parser with no notion of
"which stylesheet source" a rule came from; that's assigned by whoever
combines multiple parse results together (see "Cascade entry point"
below). `source_index` is local to one `parse/1` call.

**Selector representation:** a list of compound-selector maps, one per
step in the descendant chain, left-to-right (outermost to innermost).
`table td.total` becomes `[%{type: "table"}, %{type: "td", classes: ["total"]}]`.
Each map holds any subset of `type:`/`classes:`/`id:` keys — `.total`
alone is `%{classes: ["total"]}` with no `type:` key. `classes:` is a
list (not a single string) so a chained multi-class selector like
`.btn.btn-primary` — common in real-world CSS — keeps every class as an
independent, all-must-match requirement (`%{classes: ["btn", "btn-primary"]}`)
instead of the later class silently overwriting the earlier one. A
comma-separated selector group (`h1, h2, h3 { ... }`) expands into one
`%Rule{}` per group member, all sharing the same `declarations` and
`source_index` — the rest of the pipeline never needs to know they were
grouped.

**Styled tree (`Press.Style.Cascade` output):**

```elixir
%Press.Style.Node{
  element: %Press.HTML.Element{},
  computed: %{
    font_size: 10.5,
    color: {0, 0, 0},
    margin: %{top: 0.0, right: {:percent, 5.0}, bottom: 0.0, left: {:percent, 5.0}},
    ...
  },
  children: [...]  # [Press.Style.Node.t() | Press.Style.Text.t()]
}

%Press.Style.Text{content: "Hello world!", computed: %{font_size: 10.5, color: {0, 0, 0}, ...}}
```

Length-valued computed properties (`margin`, `padding`, `border-width`,
`width`, `height`) hold either a resolved point value (plain float) or
`{:percent, n}`. Colors are always `{r, g, b}` with `0.0..1.0`
components — the same shape `Press.PDF.ContentStream` already accepts,
so no reconversion is needed downstream in Layout/PDF writing.
`Press.Style.Text` carries `computed` too (not just `content`) because
inheritable properties like `color`/`font-size` must still reach text
nodes for Layout to render them correctly — text has no properties of
its own, but it inherits everything from its parent element.

## CSS parser

**No tokenizer/tree-builder split** (unlike Phase 2's HTML parser).
CSS's grammar is flat and regular — `selector { declarations }` repeated,
with no nesting ambiguity or auto-closing recovery to speak of — so the
two-stage split that paid for itself with HTML's nested-tag structure
would be pure overhead here. `Press.CSS.Parser` is one cohesive module
with small, independently-testable private functions (parsing rules,
selectors, declarations, specificity, and individual value types).

**Recovery on malformed input:** consistent with "CSS parsing never
fails" (general spec), a rule with no closing `}` before end of input is
dropped (mirroring the HTML tokenizer's "unterminated tag is dropped"
behavior); a declaration with no recognizable `property: value;` shape
is skipped, and parsing continues with the next declaration/rule.

**Selector syntax supported:** type, class, id, compound (`div.total#x`,
all parts must hold), and the descendant combinator (space-separated).
Comma-separated groups expand into independent rules as described above.

**Value parsing:** the parser normalizes each declaration's value into a
typed term at parse time — this is `Press.CSS.Parser`'s job, not
`Press.Style.Cascade`'s. Only the *resolution* of that typed term to a
final point value (which needs cascade context: a node's own or the
root's resolved font-size) happens later, in Cascade.

- **Color** (`color`, `background-color`, `border-color`): `#rgb`/
  `#rrggbb` hex, `rgb(r, g, b)`, and the standard CSS named-color table.
  Normalized straight to `{r, g, b}` with `0.0..1.0` components — colors
  need no cascade context, so there's no separate "typed but
  unresolved" form for them, unlike lengths.
- **Length**: number + unit (`mm`/`cm`/`in`/`pt`/`px`/`em`/`rem`/`%`),
  parsed into `{:length, number, unit_atom}` (e.g. `{:length, 1.5, :em}`) —
  Cascade later resolves this to a plain point float (or, for `%`, to
  `{:percent, number}`). Unitless `0` is accepted as `{:length, 0, :pt}`
  since zero is unambiguous regardless of unit. An unrecognized unit
  drops the whole declaration (falls back to inherited/initial), same as
  any other unsupported value.
- **`line-height`'s special grammar**: uniquely among length-valued
  properties, a bare unitless nonzero number is valid CSS
  (`line-height: 1.5`) and means "1.5× this node's own resolved
  font-size" — parsed into `{:line_height, :multiplier, 1.5}`, distinct
  from `{:length, 1.5, :em}` even though the resolved result is the same
  number of points, because `line-height`'s multiplier is *not*
  inherited as a resolved length the way other `em`-based properties are
  (a child inherits the multiplier `1.5` and reapplies it to its own
  font-size, not the parent's resolved point value — this matches real
  CSS `line-height` inheritance). An explicit unit is parsed as a normal
  `{:length, n, unit}` (with `%` rejected as an unsupported unit for
  this property specifically, per the general spec).
- **Keyword**: direct match against the valid keyword set for that
  property (`bold`/`normal`, `solid`, `disc`/`decimal`/`none`, ...),
  parsed into an atom (e.g. `:bold`). An unrecognized keyword for a
  known property drops the declaration.
- **Shorthand box properties** (`margin`, `padding`, `border-width`,
  `border-color`, `border-style`): standard CSS 1/2/3/4-value expansion,
  applied at parse time so `Press.CSS.Rule.declarations` only ever holds
  longhand keys (`"margin-top"`, `"margin-right"`, ...) — real CSS
  cascades on longhands, and expanding here means Cascade's per-property
  merge (below) never has to special-case shorthands.
  - 1 value: all four sides.
  - 2 values: top & bottom, left & right.
  - 3 values: top, left & right, bottom.
  - 4 values: top, right, bottom, left (clockwise), e.g. the general
    spec's `@page { margin: 20mm 15mm 25mm 15mm; }`.
  - **`border` shorthand**: `border: <width> <style> <color>` (any
    order, any subset present) expands into `border-width`,
    `border-style`, `border-color` — matching the general spec's
    property description ("`border(-*)` (style `solid` only, color,
    width)").

Any value that doesn't parse as a recognized color, length, keyword, or
shorthand for its property is silently dropped — never an error, per
the general spec's "unsupported value" rule.

For completeness, the general spec's remaining CSS properties map onto
these same categories: `box-sizing`, `border-collapse`,
`page-break-before`/`page-break-after` are **Keyword**-valued;
`border-spacing` is **Length**-valued. No new value category is needed
for them.

**`@page` parsing:** recognized as a distinct block (`@page { ... }`,
declarations `size`/`margin`), collected into `page_rules` rather than
matched against any selector. `size` is parsed as a keyword
(`:a4`/`:letter`/`:legal`, same atom normalization as any other
keyword value) or a two-length custom form (`{:custom, length, length}`
for `210mm 297mm`).

`margin` uses the same 1/2/3/4-value expansion algorithm as the
element-level `margin` shorthand, but the *result shape differs* from
`Press.CSS.Rule`: `PageRule.declarations["margin"]` holds a single,
already-expanded `%{top:, right:, bottom:, left:}` map (each side an
unresolved `{:length, n, unit}` term) under one `"margin"` key — it does
**not** get split into separate `"margin-top"`/`"margin-right"`/...
keys the way `Press.CSS.Rule.declarations` does. The longhand-key
splitting in the general case exists so each side can independently
win a per-property CSS cascade against competing rules of different
specificity; `@page` rules have no specificity at all (see "`@page`
resolution" below — whichever `page_rules` entry appears last simply
wins outright for the properties it sets), so there's nothing for
separate per-side keys to buy here, and keeping `margin` as one
structured value is simpler for `page_config/2` to fold.

## Selector matching and specificity

**Specificity** is `{ids, classes, types}`, summed across every compound
step of the selector. `table td.total` → 0 ids, 1 class, 2 types →
`{0, 1, 2}`. Compared lexicographically, standard CSS rules (ids beat
classes beat types).

**Matching algorithm:** walk the selector's compound steps right to
left. The last step must match the element itself. Each earlier step
must match *some* ancestor (not necessarily the immediate parent) at or
above the point reached by the previous step, preserving order. This
requires the Cascade's DOM walk to carry the ancestor chain — the same
shape of problem as the TreeBuilder's open-element stack in Phase 2,
solved the same way (an accumulator threaded through the recursive
walk).

**Class matching is token-based, not exact-string:** a compound step's
`classes:` constraint matches if *every* class name in the list appears
somewhere in the element's `class` attribute when split on whitespace —
`class="foo total bar"` matches `.total` and also `.foo.total`, same as
every browser. `id:` and `type:` are exact-string matches (an element
has at most one `id` and one tag name).

## Cascade entry point

```elixir
Press.Style.Cascade.build(dom, external_rules, embedded_rules) ::
  [Press.Style.Node.t() | Press.Style.Text.t()]
```

- `dom` — the list `Press.HTML.Parser.parse/1` returns.
- `external_rules` — the `style_rules` half of `Press.CSS.Parser.parse/1`'s
  result, from parsing `opts[:css]` (origin `1`). `[]` if `opts[:css]`
  is `nil`. (Named to avoid colliding with the generic "style_rules"
  term used elsewhere for "the non-`@page` half of a parse result" —
  this specific argument is only ever the `opts[:css]` source.)
- `embedded_rules` — same, from parsing the CSS found in embedded
  `<style>` element(s) in `dom` (origin `2`).

`Press.CSS.Parser` stays fully origin-agnostic (see "Data model" above);
`Cascade.build/3` is what assigns origin `0`/`1`/`2` to each of the three
rule sources and merges them into one list carrying `{origin, rule}`
pairs before running the algorithm below. The built-in default
stylesheet (origin `0`) is owned by a small companion module,
`Press.CSS.DefaultStylesheet`, holding the exact CSS text already fixed
in the general spec's "Default (user-agent) stylesheet" section,
parsed once via `Press.CSS.Parser.parse/1` (e.g. computed at compile
time into a module attribute — an implementation detail for the plan to
pin down, not a public contract). `Cascade.build/3` always prepends
`Press.CSS.DefaultStylesheet.rules/0` — callers never pass it in.

Extracting CSS text from embedded `<style>` elements in `dom` (finding
`<style>` nodes, concatenating their text content) is also this phase's
responsibility, since it's needed to produce the `embedded_rules`
argument above — a small helper, not a pipeline stage of its own.

## Cascade algorithm

Top-down walk of the DOM. At each element node:

1. Collect every rule in the merged `{origin, rule}` list built above
   whose selector matches this element (using the ancestor chain
   accumulated so far).
2. Sort matches by `{origin, specificity, source_index}` — origin is
   `0` (built-in default stylesheet), `1` (`opts[:css]`), or `2`
   (embedded `<style>`), reusing the ordering already fixed in the
   general spec.
3. Merge declarations **per property**: for each CSS property, the
   winning value is from whichever matching rule has the
   highest-sorting `{origin, specificity, source_index}` among rules
   that set that property. This is real CSS cascade semantics — a
   whole rule doesn't "win," each property is decided independently.
4. Resolve `font-size` first (it may itself depend on the parent's
   already-resolved `font-size` via `em`/`rem`), then resolve every
   other property on this node using that node's own resolved
   `font-size` for its `em` values (`rem` always uses the root's
   resolved `font-size`, absolute units convert directly, `%` stays
   symbolic per the correction above) — **except `line-height`, which
   step 5 below resolves instead, after inheritance is decided.**
5. For each inheritable property *except `line-height`* (the
   general-spec list minus that one property: `color`, `font-family`,
   `font-size`, `font-weight`, `font-style`, `text-align`,
   `list-style-type`, `list-style-position`), if this node's cascade
   didn't set it explicitly, inherit the parent's already-computed
   value. For non-inheritable properties, an unset value falls back to
   the property's initial value (never the parent's value).

   `line-height` inherits differently, matching real CSS: what's
   inherited is the **specified form** — the `{:line_height, :multiplier, n}`
   tuple or an explicit `{:length, n, unit}` — not a resolved point
   value, precisely so a descendant with a different font-size
   reapplies the multiplier to *its own* font-size rather than
   copying the ancestor's points verbatim (this is the behavior called
   out in "Value parsing" → "`line-height`'s special grammar" above).
   Concretely: if this node's cascade sets `line-height` explicitly,
   that's its specified form; otherwise it inherits the parent's
   specified form unchanged. Either way, *that* specified form (not the
   parent's resolved points) is what step 4 above actually resolves
   for this node — `{:line_height, :multiplier, n}` resolves to
   `n * this_node's_resolved_font_size`, an explicit length resolves the
   same as any other length. The result is `computed.line_height` (a
   plain point float, what Layout consumes), while the specified form
   itself — not the resolved float — is what continues down to this
   node's own children as "the inherited value" in step 5 for them.
6. Regroup the independently-won longhand sides back into the nested
   shape the styled tree exposes: `"margin-top"`/`"margin-right"`/
   `"margin-bottom"`/`"margin-left"` (each possibly won by a *different*
   rule, per the point of expanding them to longhands in the first
   place) become one `computed.margin = %{top:, right:, bottom:, left:}`
   map; same for `padding` and `border-width`/`border-color`/
   `border-style`. This is purely a reshaping step — no further
   winner-picking happens here, that was already decided per-longhand
   in step 3.
7. Recurse into children with this node's computed values as the new
   "parent" context. A `Press.HTML.Text` child becomes a
   `Press.Style.Text` node carrying a copy of the current inherited
   context (text has no properties/selectors of its own).

## `@page` resolution

```elixir
Press.Style.Cascade.page_config(external_page_rules, embedded_page_rules) ::
  %{size: {width_pt :: float(), height_pt :: float()},
    margin: %{top: float(), right: float(), bottom: float(), left: float()}}
```

A separate function from `build/3` — resolving the page box has nothing
to do with the per-element DOM walk. `external_page_rules`/
`embedded_page_rules` are the `page_rules` halves of parsing `opts[:css]`
and the embedded `<style>` CSS (origins `1`/`2`, same as above);
`Press.CSS.DefaultStylesheet`
contributes no `@page` rules (origin `0` is always `[]` here) since the
general spec's default stylesheet only sets element-level defaults.

`page_rules` have no selector, so no specificity applies. All
`page_rules` (origins `0`, `1`, `2` concatenated in that order) are
folded in appearance order — for each of `size`/`margin` as a whole
property (not per side), the last rule that sets it wins, same
per-property-last-wins principle as the main cascade minus the
specificity dimension. So if one `@page` rule sets `margin: 10mm` and a
later one sets `margin: 20mm 15mm`, the later one wins *entirely*
(all four sides from that single declaration) — margin sides are never
mixed and matched across different `@page` rules, unlike element-level
`margin-top`/etc. which do cascade independently per side.

Once the winning `size`/`margin` values are picked, `page_config/2`
resolves each `{:length, n, unit}` term inside them straight to points
(no `em`/`rem`/`%` context exists at the page level, so any non-absolute
unit given for `@page size`/`margin` is treated as unsupported and
dropped, falling through to the default for that property). If no
`@page` rule sets `size`/`margin` at all (including when there are zero
`@page` rules in the input), the default is **A4, 20mm margin on all
four sides**.

## Testing

- **Parser**: CSS fragments → expected `%Rule{}`/`%PageRule{}` list —
  simple/compound/descendant selectors, comma-grouped selectors,
  specificity computation, color/length/keyword value parsing, the
  1/2/3/4-value shorthand expansion for `margin`/`padding`/`border-*`,
  the `border` shorthand, `line-height`'s unitless-multiplier special
  case, and malformed declarations/rules silently dropped.
- **Selector matching**: hand-built DOM-like fixtures (not the real HTML
  parser) + already-parsed selectors → match/no-match, covering
  type/class/id/compound/descendant at various nesting depths, and
  token-based (not exact-string) class matching.
- **Cascade**: small hand-built DOM trees + hand-built rule lists →
  expected styled tree, covering: per-property merging across multiple
  matching rules, origin ordering (UA < `css:` < `<style>`),
  inheritance, `em`/`rem` resolution (including dependency on the
  parent's already-resolved `font-size`), `%` staying symbolic, and
  `line-height`'s specified-value inheritance (an ancestor sets
  `line-height: 1.5`, a descendant with a *different* font-size and no
  explicit `line-height` must get `1.5 × its own font-size` in points,
  not the ancestor's resolved point value).
- **Integration**: real HTML+CSS combining UA stylesheet + `css:` +
  embedded `<style>` together → final styled tree, confirming all three
  stages (CSS parser, selector matching, cascade) work together.
