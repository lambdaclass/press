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
# Press.CSS.Rule (style_rules)
%Press.CSS.Rule{
  selector: [%{type: "table"}, %{type: "td", class: "total"}],
  specificity: {0, 1, 2},   # {ids, classes, types}
  declarations: %{"color" => "red", "font-size" => "12px"},
  source_index: 3           # position among rules of the same origin, for tie-breaking
}

# Press.CSS.PageRule (page_rules)
%Press.CSS.PageRule{
  declarations: %{"size" => "A4", "margin" => "20mm"},
  source_index: 0
}

# Press.CSS.Parser.parse/1 result
{page_rules :: [Press.CSS.PageRule.t()], style_rules :: [Press.CSS.Rule.t()]}
```

**Selector representation:** a list of compound-selector maps, one per
step in the descendant chain, left-to-right (outermost to innermost).
`table td.total` becomes `[%{type: "table"}, %{type: "td", class: "total"}]`.
Each map holds any subset of `type:`/`class:`/`id:` keys — `.total`
alone is `%{class: "total"}` with no `type:` key. A comma-separated
selector group (`h1, h2, h3 { ... }`) expands into one `%Rule{}` per
group member, all sharing the same `declarations` and `source_index` —
the rest of the pipeline never needs to know they were grouped.

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

**Value parsing:**
- **Color** (`color`, `background-color`, `border-color`): `#rgb`/`#rrggbb`
  hex, `rgb(r, g, b)`, and the standard CSS named-color table. Normalized
  to `{r, g, b}` with `0.0..1.0` components.
- **Length**: number + unit (`12px`, `1.5em`, `50%`; unitless `0` is
  accepted since zero is unambiguous regardless of unit). An
  unrecognized unit drops the whole declaration (falls back to
  inherited/initial), same as any other unsupported value.
- **Keyword**: direct match against the valid keyword set for that
  property (`bold`/`normal`, `solid`, `disc`/`decimal`/`none`, ...); an
  unrecognized keyword for a known property drops the declaration.

Any value that doesn't parse as a recognized color, length, or keyword
for its property is silently dropped — never an error, per the general
spec's "unsupported value" rule.

**`@page` parsing:** recognized as a distinct block (`@page { ... }`,
declarations `size`/`margin`), collected into `page_rules` rather than
matched against any selector.

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

## Cascade algorithm

Top-down walk of the DOM. At each element node:

1. Collect every rule in `style_rules` whose selector matches this
   element (using the ancestor chain accumulated so far).
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
   symbolic per the correction above).
5. For each inheritable property (the list already fixed in the general
   spec: `color`, `font-family`, `font-size`, `font-weight`,
   `font-style`, `text-align`, `line-height`, `list-style-type`,
   `list-style-position`), if this node's cascade didn't set it
   explicitly, inherit the parent's already-computed value. For
   non-inheritable properties, an unset value falls back to the
   property's initial value (never the parent's value).
6. Recurse into children with this node's computed values as the new
   "parent" context. A `Press.HTML.Text` child becomes a
   `Press.Style.Text` node carrying a copy of the current inherited
   context (text has no properties/selectors of its own).

## `@page` resolution

`page_rules` have no selector, so no specificity applies. All
`page_rules` are folded in appearance order (origin, then source order)
— for each of `size`/`margin`, the last rule that sets it wins, same
per-property-last-wins principle as the main cascade minus the
specificity dimension. If no `@page` rule sets `size`/`margin` at all
(including when there are zero `@page` rules in the input), the default
is **A4, 20mm margin on all four sides**.

## Testing

- **Parser**: CSS fragments → expected `%Rule{}`/`%PageRule{}` list —
  simple/compound/descendant selectors, comma-grouped selectors,
  specificity computation, color/length/keyword value parsing,
  malformed declarations/rules silently dropped.
- **Selector matching**: hand-built DOM-like fixtures (not the real HTML
  parser) + already-parsed selectors → match/no-match, covering
  type/class/id/compound/descendant at various nesting depths.
- **Cascade**: small hand-built DOM trees + hand-built rule lists →
  expected styled tree, covering: per-property merging across multiple
  matching rules, origin ordering (UA < `css:` < `<style>`),
  inheritance, `em`/`rem` resolution (including dependency on the
  parent's already-resolved `font-size`), and `%` staying symbolic.
- **Integration**: real HTML+CSS combining UA stylesheet + `css:` +
  embedded `<style>` together → final styled tree, confirming all three
  stages (CSS parser, selector matching, cascade) work together.
