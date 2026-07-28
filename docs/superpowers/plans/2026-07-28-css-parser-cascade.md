# CSS Parser + Cascade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Press.CSS.Parser` (CSS string → rule list) and `Press.Style.Cascade` (DOM + rules → styled tree) — Phase 3 of `press`.

**Architecture:** Per the spec: a single cohesive `Press.CSS.Parser` (no tokenizer/tree-builder split — CSS's grammar is flat), small value-parsing/shorthand-expansion helpers it depends on, a `Press.CSS.Selector` module for specificity + ancestor-chain matching, a `Press.CSS.DefaultStylesheet` holding the built-in UA rules, and `Press.Style.Cascade` implementing the per-element cascade algorithm plus `@page` resolution.

**Tech Stack:** Elixir, ExUnit. No runtime dependencies.

This is Phase 3 of the `press` HTML+CSS-to-PDF project. Read
`docs/superpowers/specs/2026-07-24-css-parser-cascade-design.md` (this
plan's spec) for full design rationale. Phase 1 (`Press.PDF.*`) and
Phase 2 (`Press.HTML.*`) are separate, already-complete pipeline stages
this plan depends on for types (`Press.HTML.Element`/`Text`) but does
not modify.

Per this project's documentation standard: structs that are a public
return value of a phase's public function get real `@moduledoc`s
(`Press.CSS.Rule`, `Press.CSS.PageRule`, `Press.Style.Node`,
`Press.Style.Text`, plus the two public entry-point modules
`Press.CSS.Parser` and `Press.Style.Cascade`); purely internal helpers
(`Press.CSS.Value`, `Press.CSS.Shorthand`, `Press.CSS.Selector`,
`Press.CSS.DefaultStylesheet`) use `@moduledoc false`, matching the
convention from Phase 1/2.

**Scope note on named colors:** the spec says "the standard CSS
named-color table." This plan implements a solid ~50-name subset
(CSS Level 1/2 colors plus the most common extended names) rather than
the full 147-name CSS3 list, to keep this phase's static data
proportionate — Task 2 below adds a `TODO.md` entry for completing the
full list later.

---

## Task 1: CSS and styled-tree data structs

**Files:**
- Create: `lib/press/css/rule.ex`
- Create: `lib/press/css/page_rule.ex`
- Create: `lib/press/style/node.ex`
- Create: `lib/press/style/text.ex`

Pure data, no logic — exercised by every later task's tests.

- [ ] **Step 1: Write the implementation**

```elixir
# lib/press/css/rule.ex
defmodule Press.CSS.Rule do
  @moduledoc """
  A parsed CSS style rule (`selector { declarations }`), as produced by
  `Press.CSS.Parser.parse/1`.

  `selector` is a list of compound-selector maps in left-to-right
  (outermost-to-innermost) order — see `Press.CSS.Selector` for the
  shape and matching logic. `declarations` maps CSS property name to an
  already-parsed, typed value — box shorthands (`margin`, `padding`,
  `border-*`) are already expanded into longhand keys here, never left
  as a combined shorthand key. `source_index` is this rule's position
  among the other rules produced by the same `parse/1` call; used by
  `Press.Style.Cascade` to break ties between rules of equal
  specificity from the same stylesheet source.
  """

  @type t :: %__MODULE__{
          selector: [map()],
          specificity: {non_neg_integer(), non_neg_integer(), non_neg_integer()},
          declarations: %{String.t() => term()},
          source_index: non_neg_integer()
        }

  defstruct selector: [], specificity: {0, 0, 0}, declarations: %{}, source_index: 0
end
```

```elixir
# lib/press/css/page_rule.ex
defmodule Press.CSS.PageRule do
  @moduledoc """
  A parsed `@page { ... }` rule, as produced by `Press.CSS.Parser.parse/1`.

  Unlike `Press.CSS.Rule`, there is no selector or specificity — `@page`
  rules apply globally and the last one (in source/origin order) to set
  a given property wins outright. `declarations["margin"]`, if present,
  is already expanded into a `%{top:, right:, bottom:, left:}` map (not
  split into separate keys the way `Press.CSS.Rule` splits `margin`) —
  see the design spec's "@page parsing" section for why.
  """

  @type t :: %__MODULE__{declarations: %{String.t() => term()}, source_index: non_neg_integer()}

  defstruct declarations: %{}, source_index: 0
end
```

```elixir
# lib/press/style/node.ex
defmodule Press.Style.Node do
  @moduledoc """
  A styled element node, as produced by `Press.Style.Cascade.build/3`.

  `computed` maps property name (as an atom, e.g. `:font_size`,
  `:margin`) to its resolved value: colors are `{r, g, b}` floats in
  `0.0..1.0`; lengths are a point float, except `%`-valued lengths,
  which stay `{:percent, n}` since resolving them needs the containing
  block's width — a layout-time concept `Press.Style.Cascade` doesn't
  have. See the design spec for the full computed-property list.
  """

  @type t :: %__MODULE__{
          element: Press.HTML.Element.t(),
          computed: map(),
          children: [t() | Press.Style.Text.t()]
        }

  defstruct element: nil, computed: %{}, children: []
end
```

```elixir
# lib/press/style/text.ex
defmodule Press.Style.Text do
  @moduledoc """
  A styled text node, as produced by `Press.Style.Cascade.build/3`.

  Text has no properties or selectors of its own, but still carries a
  `computed` map — a copy of whatever it inherited from its parent
  element — since properties like `color`/`font-size` must reach text
  for Layout to render it correctly.
  """

  @type t :: %__MODULE__{content: String.t(), computed: map()}

  defstruct content: "", computed: %{}
end
```

- [ ] **Step 2: Compile and confirm no errors**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/press/css/rule.ex lib/press/css/page_rule.ex lib/press/style/node.ex lib/press/style/text.ex
git commit -m "Add CSS rule and styled-tree data structs"
```

---

## Task 2: Value parsers (color, length, line-height, keyword)

**Files:**
- Create: `lib/press/css/value.ex`
- Test: `test/press/css/value_test.exs`

Shared parsing helpers `Press.CSS.Parser` (Task 5) calls per declaration
value. No cascade context needed here — see the design spec's "Value
parsing" section.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Press.CSS.ValueTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Value

  describe "parse_color/1" do
    test "parses 6-digit and 3-digit hex" do
      assert Value.parse_color("#ff0000") == {:ok, {1.0, 0.0, 0.0}}
      assert Value.parse_color("#F00") == {:ok, {1.0, 0.0, 0.0}}
    end

    test "parses rgb()" do
      assert Value.parse_color("rgb(255, 0, 0)") == {:ok, {1.0, 0.0, 0.0}}
    end

    test "parses named colors case-insensitively" do
      assert Value.parse_color("Red") == {:ok, {1.0, 0.0, 0.0}}
      assert Value.parse_color("black") == {:ok, {0.0, 0.0, 0.0}}
    end

    test "rejects unrecognized color text" do
      assert Value.parse_color("notacolor") == :error
    end
  end

  describe "parse_length/1" do
    test "parses a number with a unit" do
      assert Value.parse_length("12px") == {:ok, {:length, 12.0, :px}}
      assert Value.parse_length("1.5em") == {:ok, {:length, 1.5, :em}}
      assert Value.parse_length("50%") == {:ok, {:length, 50.0, :percent}}
    end

    test "accepts unitless 0" do
      assert Value.parse_length("0") == {:ok, {:length, 0, :pt}}
    end

    test "rejects an unrecognized unit" do
      assert Value.parse_length("12furlongs") == :error
    end

    test "rejects a nonzero unitless number" do
      assert Value.parse_length("12") == :error
    end
  end

  describe "parse_line_height/1" do
    test "parses a bare unitless number as a multiplier" do
      assert Value.parse_line_height("1.5") == {:ok, {:line_height, :multiplier, 1.5}}
    end

    test "parses an explicit length" do
      assert Value.parse_line_height("14pt") == {:ok, {:length, 14.0, :pt}}
    end

    test "rejects percent" do
      assert Value.parse_line_height("150%") == :error
    end
  end

  describe "parse_keyword/2" do
    test "matches a valid keyword" do
      assert Value.parse_keyword("bold", [:normal, :bold]) == {:ok, :bold}
    end

    test "is case-insensitive" do
      assert Value.parse_keyword("BOLD", [:normal, :bold]) == {:ok, :bold}
    end

    test "rejects a keyword not in the valid set" do
      assert Value.parse_keyword("italic", [:normal, :bold]) == :error
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/css/value_test.exs`
Expected: FAIL — `Press.CSS.Value` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.CSS.Value do
  @moduledoc false

  @named_colors %{
    "black" => "000000", "white" => "FFFFFF", "red" => "FF0000", "green" => "008000",
    "blue" => "0000FF", "yellow" => "FFFF00", "orange" => "FFA500", "purple" => "800080",
    "pink" => "FFC0CB", "brown" => "A52A2A", "gray" => "808080", "grey" => "808080",
    "silver" => "C0C0C0", "gold" => "FFD700", "maroon" => "800000", "navy" => "000080",
    "teal" => "008080", "olive" => "808000", "lime" => "00FF00", "aqua" => "00FFFF",
    "cyan" => "00FFFF", "fuchsia" => "FF00FF", "magenta" => "FF00FF", "indigo" => "4B0082",
    "violet" => "EE82EE", "turquoise" => "40E0D0", "coral" => "FF7F50", "salmon" => "FA8072",
    "khaki" => "F0E68C", "tan" => "D2B48C", "beige" => "F5F5DC", "ivory" => "FFFFF0",
    "lavender" => "E6E6FA", "plum" => "DDA0DD", "orchid" => "DA70D6", "chocolate" => "D2691E",
    "crimson" => "DC143C", "skyblue" => "87CEEB", "steelblue" => "4682B4",
    "royalblue" => "4169E1", "forestgreen" => "228B22", "seagreen" => "2E8B57",
    "springgreen" => "00FF7F", "yellowgreen" => "9ACD32", "olivedrab" => "6B8E23",
    "darkgreen" => "006400", "darkblue" => "00008B", "darkred" => "8B0000",
    "lightblue" => "ADD8E6", "lightgreen" => "90EE90", "lightgray" => "D3D3D3",
    "lightgrey" => "D3D3D3", "lightyellow" => "FFFFE0", "lightpink" => "FFB6C1",
    "darkgray" => "A9A9A9", "dimgray" => "696969", "slategray" => "708090",
    "whitesmoke" => "F5F5F5"
  }

  @length_regex ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)$/
  @zero_regex ~r/^0(?:\.0+)?$/
  @rgb_regex ~r/^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/
  @multiplier_regex ~r/^-?\d+(?:\.\d+)?$/
  @absolute_length_regex ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem)$/

  def parse_color(str) do
    str = String.trim(str)

    case parse_hex_color(str) do
      {:ok, rgb} -> {:ok, rgb}
      :error -> parse_rgb_or_named(str)
    end
  end

  defp parse_rgb_or_named(str) do
    case Regex.run(@rgb_regex, str) do
      [_, r, g, b] ->
        {:ok, {String.to_integer(r) / 255.0, String.to_integer(g) / 255.0, String.to_integer(b) / 255.0}}

      nil ->
        case Map.fetch(@named_colors, String.downcase(str)) do
          {:ok, hex} -> parse_hex_color("#" <> hex)
          :error -> :error
        end
    end
  end

  defp parse_hex_color("#" <> hex) when byte_size(hex) in [3, 6] do
    expanded =
      case byte_size(hex) do
        3 -> hex |> String.graphemes() |> Enum.map(&(&1 <> &1)) |> Enum.join()
        6 -> hex
      end

    case Integer.parse(expanded, 16) do
      {value, ""} ->
        r = div(value, 65536)
        g = value |> div(256) |> rem(256)
        b = rem(value, 256)
        {:ok, {r / 255.0, g / 255.0, b / 255.0}}

      _ ->
        :error
    end
  end

  defp parse_hex_color(_), do: :error

  def parse_length(str) do
    str = String.trim(str)

    cond do
      Regex.match?(@zero_regex, str) ->
        {:ok, {:length, 0, :pt}}

      match = Regex.run(@length_regex, str) ->
        [_, number, unit] = match
        {:ok, {:length, parse_number(number), unit_atom(unit)}}

      true ->
        :error
    end
  end

  def parse_line_height(str) do
    str = String.trim(str)

    cond do
      Regex.match?(@multiplier_regex, str) ->
        {:ok, {:line_height, :multiplier, parse_number(str)}}

      match = Regex.run(@absolute_length_regex, str) ->
        [_, number, unit] = match
        {:ok, {:length, parse_number(number), String.to_atom(unit)}}

      true ->
        :error
    end
  end

  def parse_keyword(str, valid_keywords) do
    atom = str |> String.trim() |> String.downcase() |> String.to_atom()
    if atom in valid_keywords, do: {:ok, atom}, else: :error
  end

  defp unit_atom("%"), do: :percent
  defp unit_atom(unit), do: String.to_atom(unit)

  defp parse_number(str) do
    {value, ""} = Float.parse(str)
    value
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/css/value_test.exs`
Expected: PASS (14 tests, 0 failures)

- [ ] **Step 5: Add the deferred full-color-list TODO and commit**

Add to `TODO.md`:

```markdown
- Expand `Press.CSS.Value`'s named-color table from ~55 common CSS
  color names to the full 147-name CSS Color Module Level 3 list.
```

```bash
git add lib/press/css/value.ex test/press/css/value_test.exs TODO.md
git commit -m "Add CSS color/length/keyword value parsers"
```

---

## Task 3: Shorthand box-property expansion

**Files:**
- Create: `lib/press/css/shorthand.ex`
- Test: `test/press/css/shorthand_test.exs`

Standard CSS 1/2/3/4-value expansion for `margin`/`padding`/
`border-width`/`border-color`/`border-style`, plus the `border`
compound shorthand. Depends on `Press.CSS.Value` (Task 2). Two shapes
are needed (see the design spec's "@page parsing" section): element-level
shorthands expand into separate longhand keys; `Press.CSS.Parser` (Task
5) uses `expand_box/3` for elements and `expand_page_margin/1` for
`@page`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Press.CSS.ShorthandTest do
  use ExUnit.Case, async: true

  alias Press.CSS.{Shorthand, Value}

  describe "expand_box/3" do
    test "1 value applies to all four sides" do
      assert Shorthand.expand_box("margin", "1em", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :em},
                  "margin-right" => {:length, 1.0, :em},
                  "margin-bottom" => {:length, 1.0, :em},
                  "margin-left" => {:length, 1.0, :em}
                }}
    end

    test "2 values: top/bottom, left/right" do
      assert Shorthand.expand_box("margin", "1em 2em", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :em},
                  "margin-right" => {:length, 2.0, :em},
                  "margin-bottom" => {:length, 1.0, :em},
                  "margin-left" => {:length, 2.0, :em}
                }}
    end

    test "3 values: top, left/right, bottom" do
      assert Shorthand.expand_box("margin", "1pt 2pt 3pt", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 1.0, :pt},
                  "margin-right" => {:length, 2.0, :pt},
                  "margin-bottom" => {:length, 3.0, :pt},
                  "margin-left" => {:length, 2.0, :pt}
                }}
    end

    test "4 values: top, right, bottom, left" do
      assert Shorthand.expand_box("margin", "20mm 15mm 25mm 15mm", &Value.parse_length/1) ==
               {:ok,
                %{
                  "margin-top" => {:length, 20.0, :mm},
                  "margin-right" => {:length, 15.0, :mm},
                  "margin-bottom" => {:length, 25.0, :mm},
                  "margin-left" => {:length, 15.0, :mm}
                }}
    end

    test "rejects more than 4 values" do
      assert Shorthand.expand_box("margin", "1pt 2pt 3pt 4pt 5pt", &Value.parse_length/1) == :error
    end

    test "rejects a value that fails the given parser" do
      assert Shorthand.expand_box("margin", "1pt notalength", &Value.parse_length/1) == :error
    end
  end

  describe "expand_page_margin/1" do
    test "expands into a single top/right/bottom/left map" do
      assert Shorthand.expand_page_margin("20mm 15mm 25mm 15mm") ==
               {:ok,
                %{
                  top: {:length, 20.0, :mm},
                  right: {:length, 15.0, :mm},
                  bottom: {:length, 25.0, :mm},
                  left: {:length, 15.0, :mm}
                }}
    end

    test "1 value applies to all four sides" do
      assert Shorthand.expand_page_margin("20mm") ==
               {:ok,
                %{
                  top: {:length, 20.0, :mm},
                  right: {:length, 20.0, :mm},
                  bottom: {:length, 20.0, :mm},
                  left: {:length, 20.0, :mm}
                }}
    end
  end

  describe "expand_border/1" do
    test "expands width, style, and color to all four sides, regardless of order" do
      expected =
        {:ok,
         %{
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
         }}

      assert Shorthand.expand_border("1px solid #000000") == expected
      assert Shorthand.expand_border("solid #000000 1px") == expected
    end

    test "accepts a subset of the three parts" do
      assert Shorthand.expand_border("1px solid") ==
               {:ok,
                %{
                  "border-width-top" => {:length, 1.0, :px},
                  "border-width-right" => {:length, 1.0, :px},
                  "border-width-bottom" => {:length, 1.0, :px},
                  "border-width-left" => {:length, 1.0, :px},
                  "border-style-top" => :solid,
                  "border-style-right" => :solid,
                  "border-style-bottom" => :solid,
                  "border-style-left" => :solid
                }}
    end

    test "rejects a part that isn't a valid width, style, or color" do
      assert Shorthand.expand_border("1px solid dashed") == :error
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/css/shorthand_test.exs`
Expected: FAIL — `Press.CSS.Shorthand` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.CSS.Shorthand do
  @moduledoc false

  alias Press.CSS.Value

  def expand_box(property, raw_value, parse_fun) do
    with {:ok, [top, right, bottom, left]} <- expand_sides(String.split(raw_value)),
         {:ok, t} <- parse_fun.(top),
         {:ok, r} <- parse_fun.(right),
         {:ok, b} <- parse_fun.(bottom),
         {:ok, l} <- parse_fun.(left) do
      {:ok,
       %{
         "#{property}-top" => t,
         "#{property}-right" => r,
         "#{property}-bottom" => b,
         "#{property}-left" => l
       }}
    else
      :error -> :error
    end
  end

  def expand_page_margin(raw_value) do
    with {:ok, [top, right, bottom, left]} <- expand_sides(String.split(raw_value)),
         {:ok, t} <- Value.parse_length(top),
         {:ok, r} <- Value.parse_length(right),
         {:ok, b} <- Value.parse_length(bottom),
         {:ok, l} <- Value.parse_length(left) do
      {:ok, %{top: t, right: r, bottom: b, left: l}}
    else
      :error -> :error
    end
  end

  @sides ~w(top right bottom left)

  def expand_border(raw_value) do
    case raw_value |> String.split() |> Enum.reduce({:ok, %{}}, &expand_border_part/2) do
      {:ok, parts} -> {:ok, fan_out_to_sides(parts)}
      :error -> :error
    end
  end

  # The `border` shorthand always applies the same width/style/color to
  # all four sides (unlike `margin`/`padding`, there's no 1/2/3/4-value
  # per-side form of the compound `border` shorthand in CSS). Still fan
  # each resolved property out to "<property>-top/right/bottom/left" so
  # Press.Style.Cascade's per-property merge (which only ever looks for
  # longhand keys, same as every other box property) sees it correctly
  # instead of a flat "border-width"/"border-style"/"border-color" key
  # nothing else in the pipeline reads.
  defp fan_out_to_sides(parts) do
    Enum.reduce(parts, %{}, fn {property, value}, acc ->
      Enum.reduce(@sides, acc, fn side, acc2 -> Map.put(acc2, "#{property}-#{side}", value) end)
    end)
  end

  defp expand_border_part(_part, :error), do: :error

  defp expand_border_part(part, {:ok, acc}) do
    cond do
      match?({:ok, _}, Value.parse_length(part)) ->
        {:ok, v} = Value.parse_length(part)
        {:ok, Map.put(acc, "border-width", v)}

      match?({:ok, _}, Value.parse_keyword(part, [:solid])) ->
        {:ok, Map.put(acc, "border-style", :solid)}

      match?({:ok, _}, Value.parse_color(part)) ->
        {:ok, v} = Value.parse_color(part)
        {:ok, Map.put(acc, "border-color", v)}

      true ->
        :error
    end
  end

  defp expand_sides([a]), do: {:ok, [a, a, a, a]}
  defp expand_sides([a, b]), do: {:ok, [a, b, a, b]}
  defp expand_sides([a, b, c]), do: {:ok, [a, b, c, b]}
  defp expand_sides([a, b, c, d]), do: {:ok, [a, b, c, d]}
  defp expand_sides(_other), do: :error
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/css/shorthand_test.exs`
Expected: PASS (11 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/css/shorthand.ex test/press/css/shorthand_test.exs
git commit -m "Add CSS box-shorthand (margin/padding/border) expansion"
```

---

## Task 4: Selector parsing, specificity, and ancestor-chain matching

**Files:**
- Create: `lib/press/css/selector.ex`
- Test: `test/press/css/selector_test.exs`

Parses selector text into the compound-map list `Press.CSS.Rule` stores,
computes specificity, and matches a parsed selector against an element
plus its ancestor chain. No dependency on Task 2/3 — this is pure
selector-syntax logic.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Press.CSS.SelectorTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Selector

  describe "parse/1" do
    test "parses a bare type selector" do
      assert Selector.parse("div") == [%{type: "div"}]
    end

    test "parses a bare class selector" do
      assert Selector.parse(".total") == [%{classes: ["total"]}]
    end

    test "parses a bare id selector" do
      assert Selector.parse("#header") == [%{id: "header"}]
    end

    test "parses a compound selector" do
      assert Selector.parse("div.total#x") == [%{type: "div", classes: ["total"], id: "x"}]
    end

    test "parses a descendant chain" do
      assert Selector.parse("table td.total") ==
               [%{type: "table"}, %{type: "td", classes: ["total"]}]
    end

    test "parses multiple classes chained on one compound" do
      assert Selector.parse(".foo.bar") == [%{classes: ["foo", "bar"]}]
    end
  end

  describe "specificity/1" do
    test "counts ids, classes, and types across all compound steps" do
      assert Selector.specificity([%{type: "table"}, %{type: "td", classes: ["total"]}]) ==
               {0, 1, 2}

      assert Selector.specificity([%{id: "x"}]) == {1, 0, 0}
      assert Selector.specificity([%{type: "div"}]) == {0, 0, 1}
    end

    test "counts each chained class separately" do
      assert Selector.specificity([%{classes: ["foo", "bar"]}]) == {0, 2, 0}
    end
  end

  describe "matches?/3" do
    test "a bare type selector matches the element itself" do
      element = %Press.HTML.Element{tag: "div", attrs: %{}}
      assert Selector.matches?([%{type: "div"}], element, [])
      refute Selector.matches?([%{type: "span"}], element, [])
    end

    test "class matching is token-based" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "foo total bar"}}
      assert Selector.matches?([%{classes: ["total"]}], element, [])
      refute Selector.matches?([%{classes: ["missing"]}], element, [])
    end

    test "a chained multi-class selector requires every class to be present" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "btn btn-primary"}}
      assert Selector.matches?([%{classes: ["btn", "btn-primary"]}], element, [])
      refute Selector.matches?([%{classes: ["btn", "btn-secondary"]}], element, [])
    end

    test "id matching is exact" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"id" => "header"}}
      assert Selector.matches?([%{id: "header"}], element, [])
    end

    test "a compound selector requires every part to hold" do
      element = %Press.HTML.Element{tag: "div", attrs: %{"class" => "total"}}
      assert Selector.matches?([%{type: "div", classes: ["total"]}], element, [])
      refute Selector.matches?([%{type: "span", classes: ["total"]}], element, [])
    end

    test "a descendant combinator matches an ancestor at any depth, not just the immediate parent" do
      element = %Press.HTML.Element{tag: "td", attrs: %{}}
      grandparent = %Press.HTML.Element{tag: "table", attrs: %{}}
      parent = %Press.HTML.Element{tag: "tr", attrs: %{}}

      assert Selector.matches?([%{type: "table"}, %{type: "td"}], element, [parent, grandparent])
    end

    test "a descendant combinator fails if no ancestor matches" do
      element = %Press.HTML.Element{tag: "td", attrs: %{}}
      parent = %Press.HTML.Element{tag: "tr", attrs: %{}}

      refute Selector.matches?([%{type: "table"}, %{type: "td"}], element, [parent])
    end

    test "the last selector step must match the element, not an ancestor" do
      element = %Press.HTML.Element{tag: "tr", attrs: %{}}
      grandparent = %Press.HTML.Element{tag: "table", attrs: %{}}

      refute Selector.matches?([%{type: "table"}, %{type: "td"}], element, [grandparent])
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/css/selector_test.exs`
Expected: FAIL — `Press.CSS.Selector` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.CSS.Selector do
  @moduledoc false

  def parse(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.map(&parse_compound/1)
  end

  defp parse_compound(text) do
    case Regex.run(~r/^([A-Za-z][A-Za-z0-9_-]*)?((?:[.#][A-Za-z0-9_-]+)*)$/, text) do
      [_, type, rest] ->
        %{}
        |> maybe_put_type(type)
        |> apply_class_and_id(rest)

      nil ->
        %{}
    end
  end

  defp maybe_put_type(map, ""), do: map
  defp maybe_put_type(map, type), do: Map.put(map, :type, type)

  defp apply_class_and_id(map, rest) do
    ~r/([.#])([A-Za-z0-9_-]+)/
    |> Regex.scan(rest)
    |> Enum.reduce(map, fn
      [_, ".", name], acc -> Map.update(acc, :classes, [name], &(&1 ++ [name]))
      [_, "#", name], acc -> Map.put(acc, :id, name)
    end)
  end

  def specificity(compounds) do
    Enum.reduce(compounds, {0, 0, 0}, fn compound, {ids, classes, types} ->
      {
        ids + bool_to_int(Map.has_key?(compound, :id)),
        classes + length(Map.get(compound, :classes, [])),
        types + bool_to_int(Map.has_key?(compound, :type))
      }
    end)
  end

  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  def matches?(compounds, element, ancestors) do
    case Enum.reverse(compounds) do
      [last | rest] -> compound_matches?(last, element) and match_ancestors(rest, ancestors)
      [] -> false
    end
  end

  defp match_ancestors([], _ancestors), do: true
  defp match_ancestors([_compound | _rest], []), do: false

  defp match_ancestors([compound | rest] = compounds, [ancestor | older]) do
    if compound_matches?(compound, ancestor) do
      match_ancestors(rest, older)
    else
      match_ancestors(compounds, older)
    end
  end

  defp compound_matches?(compound, element) do
    type_matches?(compound, element) and id_matches?(compound, element) and
      class_matches?(compound, element)
  end

  defp type_matches?(%{type: type}, element), do: element.tag == type
  defp type_matches?(_compound, _element), do: true

  defp id_matches?(%{id: id}, element), do: Map.get(element.attrs, "id") == id
  defp id_matches?(_compound, _element), do: true

  defp class_matches?(%{classes: classes}, element) do
    element_classes =
      element.attrs
      |> Map.get("class", "")
      |> String.split()

    Enum.all?(classes, &(&1 in element_classes))
  end

  defp class_matches?(_compound, _element), do: true
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/css/selector_test.exs`
Expected: PASS (16 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/css/selector.ex test/press/css/selector_test.exs
git commit -m "Add CSS selector parsing, specificity, and matching"
```

---

## Task 5: `Press.CSS.Parser` — full CSS text to rules

**Files:**
- Create: `lib/press/css/parser.ex`
- Test: `test/press/css/parser_test.exs`

Ties together Tasks 2-4: splits CSS text into `selector { declarations }`
/ `@page { declarations }` blocks, dispatches each declaration's value to
the right parser (color/length/line-height/keyword/shorthand/font-family),
and produces `{page_rules, style_rules}`. This is the phase's public
parsing entry point — real docs, not `@moduledoc false`.

**Design notes not spelled out in the spec:**
- **`font-family`** doesn't fit the Color/Length/Keyword/Shorthand
  categories cleanly — it maps free-form CSS font names to one of three
  family atoms (`:helvetica`/`:times`/`:courier`) via a small alias
  table (`"arial"`/`"sans-serif"` → `:helvetica`, etc.), and **always**
  resolves to one of them (falling back to `:helvetica` for anything
  unrecognized) rather than dropping the declaration — per the general
  spec's "unknown font-family is not an error, falls back to Helvetica."
  This is stronger than the generic "unsupported value is dropped"
  rule. Combining this family choice with `font-weight`/`font-style`
  into one of the 14 `Press.PDF.Fonts` atoms is Phase 4 (Layout)'s job,
  not this phase's — Cascade just carries the three separately.
- **Comments** (`/* ... */`) are stripped before block-splitting, so
  they can't interfere with brace matching.
- **Unterminated rule** (`{` with no matching `}` before end of input)
  is dropped, mirroring Phase 2's tokenizer.

- [ ] **Step 1: Write the failing tests**

```elixir
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
    assert page.declarations == %{"size" => {:custom, {:length, 210.0, :mm}, {:length, 297.0, :mm}}}
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/css/parser_test.exs`
Expected: FAIL — `Press.CSS.Parser` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.CSS.Parser do
  @moduledoc """
  Parses a CSS string into `{page_rules, style_rules}`.

  Never fails: a rule with no closing `}` is dropped, and a declaration
  that doesn't parse as a recognized property/value is silently
  skipped, same as a browser. See
  `docs/superpowers/specs/2026-07-24-css-parser-cascade-design.md` for
  the full design.

  ## Examples

      iex> Press.CSS.Parser.parse("h1 { color: red; }")
      {[], [%Press.CSS.Rule{selector: [%{type: "h1"}], specificity: {0, 0, 1}, declarations: %{"color" => {1.0, 0.0, 0.0}}, source_index: 0}]}

  """

  alias Press.CSS.{PageRule, Rule, Selector, Shorthand, Value}

  @box_shorthand_properties %{
    "margin" => &Value.parse_length/1,
    "padding" => &Value.parse_length/1,
    "border-width" => &Value.parse_length/1,
    "border-color" => &Value.parse_color/1
  }

  @color_properties ~w(color background-color)
  @length_properties ~w(font-size width height border-spacing)

  @keyword_properties %{
    "font-weight" => [:normal, :bold],
    "font-style" => [:normal, :italic],
    "text-align" => [:left, :right, :center],
    "list-style-type" => [:disc, :decimal, :none],
    "list-style-position" => [:outside, :inside],
    "box-sizing" => [:"content-box", :"border-box"],
    "border-collapse" => [:collapse, :separate],
    "page-break-before" => [:auto, :always],
    "page-break-after" => [:auto, :always]
  }

  @font_family_aliases %{
    "helvetica" => :helvetica,
    "arial" => :helvetica,
    "sans-serif" => :helvetica,
    "times" => :times,
    "times new roman" => :times,
    "serif" => :times,
    "courier" => :courier,
    "courier new" => :courier,
    "monospace" => :courier
  }

  @spec parse(String.t()) :: {[PageRule.t()], [Rule.t()]}
  def parse(css) when is_binary(css) do
    {page_acc, style_acc, _page_idx, _style_idx} =
      css
      |> strip_comments()
      |> split_blocks()
      |> Enum.reduce({[], [], 0, 0}, &process_block/2)

    {Enum.reverse(page_acc), Enum.reverse(style_acc)}
  end

  defp strip_comments(css), do: Regex.replace(~r/\/\*.*?\*\//s, css, "")

  defp split_blocks(css), do: css |> do_split_blocks([]) |> Enum.reverse()

  defp do_split_blocks(css, acc) do
    case :binary.match(css, "{") do
      :nomatch ->
        acc

      {open_pos, _len} ->
        case :binary.match(css, "}") do
          :nomatch ->
            acc

          {close_pos, _len} when close_pos > open_pos ->
            header = css |> binary_part(0, open_pos) |> String.trim()
            body = css |> binary_part(open_pos + 1, close_pos - open_pos - 1) |> String.trim()
            rest = binary_part(css, close_pos + 1, byte_size(css) - close_pos - 1)
            do_split_blocks(rest, [{header, body} | acc])

          {close_pos, _len} ->
            rest = binary_part(css, close_pos + 1, byte_size(css) - close_pos - 1)
            do_split_blocks(rest, acc)
        end
    end
  end

  defp process_block({"", _body}, state), do: state

  defp process_block({header, body}, {page_acc, style_acc, page_idx, style_idx}) do
    if String.starts_with?(header, "@page") do
      rule = %PageRule{declarations: parse_page_declarations(body), source_index: page_idx}
      {[rule | page_acc], style_acc, page_idx + 1, style_idx}
    else
      declarations = parse_declarations(body)

      new_rules =
        header
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(fn selector_text ->
          compounds = Selector.parse(selector_text)

          %Rule{
            selector: compounds,
            specificity: Selector.specificity(compounds),
            declarations: declarations,
            source_index: style_idx
          }
        end)

      {page_acc, Enum.reverse(new_rules) ++ style_acc, page_idx, style_idx + 1}
    end
  end

  defp parse_declarations(body) do
    body
    |> split_declarations()
    |> Enum.reduce(%{}, fn {property, value}, acc ->
      case parse_declaration(property, value) do
        {:ok, parsed} -> Map.merge(acc, parsed)
        :error -> acc
      end
    end)
  end

  defp split_declarations(body) do
    body
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.split(&1, ":", parts: 2))
    |> Enum.filter(&match?([_, _], &1))
    |> Enum.map(fn [prop, value] -> {prop |> String.trim() |> String.downcase(), String.trim(value)} end)
  end

  defp parse_declaration("border", value), do: Shorthand.expand_border(value)

  defp parse_declaration("border-style", value) do
    # Not in @box_shorthand_properties: a closure (as opposed to a
    # remote function capture like &Value.parse_length/1) can't be
    # stored in a module attribute — Elixir can't escape it into the
    # BEAM constant pool at compile time. Handled as its own clause
    # instead.
    Shorthand.expand_box("border-style", value, fn v -> Value.parse_keyword(v, [:solid]) end)
  end

  defp parse_declaration("font-family", value) do
    name = value |> String.trim() |> String.trim("\"") |> String.trim("'") |> String.downcase()
    {:ok, %{"font-family" => Map.get(@font_family_aliases, name, :helvetica)}}
  end

  defp parse_declaration("line-height", value) do
    with {:ok, v} <- Value.parse_line_height(value), do: {:ok, %{"line-height" => v}}
  end

  defp parse_declaration(property, value) do
    cond do
      parse_fun = Map.get(@box_shorthand_properties, property) ->
        Shorthand.expand_box(property, value, parse_fun)

      property in @color_properties ->
        with {:ok, v} <- Value.parse_color(value), do: {:ok, %{property => v}}

      property in @length_properties ->
        with {:ok, v} <- Value.parse_length(value), do: {:ok, %{property => v}}

      valid_keywords = Map.get(@keyword_properties, property) ->
        with {:ok, v} <- Value.parse_keyword(value, valid_keywords), do: {:ok, %{property => v}}

      true ->
        :error
    end
  end

  defp parse_page_declarations(body) do
    body
    |> split_declarations()
    |> Enum.reduce(%{}, fn {property, value}, acc ->
      case parse_page_declaration(property, value) do
        {:ok, parsed} -> Map.merge(acc, parsed)
        :error -> acc
      end
    end)
  end

  defp parse_page_declaration("margin", value) do
    with {:ok, v} <- Shorthand.expand_page_margin(value), do: {:ok, %{"margin" => v}}
  end

  defp parse_page_declaration("size", value) do
    case Value.parse_keyword(value, [:a4, :letter, :legal]) do
      {:ok, kw} ->
        {:ok, %{"size" => kw}}

      :error ->
        case String.split(value) do
          [w, h] ->
            with {:ok, wv} <- Value.parse_length(w), {:ok, hv} <- Value.parse_length(h) do
              {:ok, %{"size" => {:custom, wv, hv}}}
            else
              _ -> :error
            end

          _other ->
            :error
        end
    end
  end

  defp parse_page_declaration(_property, _value), do: :error
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/css/parser_test.exs`
Expected: PASS (14 tests, 1 doctest, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/css/parser.ex test/press/css/parser_test.exs
git commit -m "Add Press.CSS.Parser public entry point"
```

---

## Task 6: `Press.CSS.DefaultStylesheet` — the built-in UA rules

**Files:**
- Create: `lib/press/css/default_stylesheet.ex`
- Test: `test/press/css/default_stylesheet_test.exs`

Holds the exact CSS text from the general spec's "Default (user-agent)
stylesheet" section, parsed once at compile time via `Press.CSS.Parser`
(Task 5) rather than re-parsed on every `Cascade.build/3` call.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Press.CSS.DefaultStylesheetTest do
  use ExUnit.Case, async: true

  alias Press.CSS.DefaultStylesheet

  test "produces rules for the tags the general spec's default stylesheet covers" do
    rules = DefaultStylesheet.rules()

    assert Enum.any?(rules, &(&1.selector == [%{type: "strong"}]))
    assert Enum.any?(rules, &(&1.selector == [%{type: "h1"}]))
    assert Enum.any?(rules, &(&1.selector == [%{type: "ol"}]))
  end

  test "h1 gets the expected font-size and margin declarations" do
    rules = DefaultStylesheet.rules()
    h1_rule = Enum.find(rules, &(&1.selector == [%{type: "h1"}]))

    assert h1_rule.declarations["font-size"] == {:length, 24.0, :pt}
    assert h1_rule.declarations["margin-top"] == {:length, 0.67, :em}
  end

  test "produces no @page rules" do
    assert DefaultStylesheet.page_rules() == []
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/css/default_stylesheet_test.exs`
Expected: FAIL — `Press.CSS.DefaultStylesheet` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.CSS.DefaultStylesheet do
  @moduledoc false

  alias Press.CSS.Parser

  @css """
  strong, b { font-weight: bold; }
  em, i { font-style: italic; }
  th { font-weight: bold; text-align: center; }
  h1 { font-size: 24pt; margin: 0.67em 0; }
  h2 { font-size: 18pt; margin: 0.75em 0; }
  h3 { font-size: 14pt; margin: 0.83em 0; }
  h4 { font-size: 12pt; margin: 1.12em 0; }
  h5 { font-size: 10pt; margin: 1.5em 0; }
  h6 { font-size: 8pt; margin: 1.67em 0; }
  p { margin: 1em 0; }
  ul, ol { list-style-position: outside; margin: 1em 0; }
  ul { list-style-type: disc; }
  ol { list-style-type: decimal; }
  """

  {parsed_page_rules, parsed_style_rules} = Parser.parse(@css)
  @parsed_page_rules parsed_page_rules
  @parsed_style_rules parsed_style_rules

  def rules, do: @parsed_style_rules
  def page_rules, do: @parsed_page_rules
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/css/default_stylesheet_test.exs`
Expected: PASS (3 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/css/default_stylesheet.ex test/press/css/default_stylesheet_test.exs
git commit -m "Add built-in UA default stylesheet, parsed at compile time"
```

---

## Task 7: `Press.Style.Cascade.build/3` — the per-element cascade

**Files:**
- Create: `lib/press/style/cascade.ex`
- Test: `test/press/style/cascade_test.exs`

The main algorithm from the design spec: collect matching rules per
element (using `Press.CSS.Selector`), sort by `{origin, specificity,
source_index}`, merge per property, resolve units, apply inheritance
(with `line-height`'s specified-value carve-out), regroup box longhands,
recurse. Tests build `Press.HTML.Element`/`Text`/`Press.CSS.Rule`
fixtures directly rather than going through the real HTML/CSS parsers.

**Design note not spelled out in the spec: what "root font-size" means
for `rem`.** Phase 2's HTML parser doesn't do implicit `<html>`/`<body>`
wrapping, so a bare fragment can have multiple top-level siblings with
no single common root element — there's no one element whose own CSS
could define "the root font-size" the way a real browser's `<html>`
element does. This plan defines `rem` as always relative to the
**initial** font-size (12pt, fixed), not to a dynamically-resolved
root element's computed font-size. This is a deliberate scope
simplification following directly from Phase 2's fragment model, not
an oversight.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Press.Style.CascadeTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Rule
  alias Press.HTML
  alias Press.Style.{Cascade, Node, Text}

  defp rule(selector_text, specificity, declarations, source_index \\ 0) do
    %Rule{
      selector: Press.CSS.Selector.parse(selector_text),
      specificity: specificity,
      declarations: declarations,
      source_index: source_index
    }
  end

  test "matches a rule and applies its declarations" do
    dom = [%HTML.Element{tag: "p", attrs: %{}, children: []}]
    rules = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.color == {1.0, 0.0, 0.0}
  end

  test "merges declarations per property across multiple matching rules by specificity" do
    dom = [%HTML.Element{tag: "p", attrs: %{"class" => "note"}, children: []}]

    rules = [
      rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}, "font-weight" => :bold}),
      rule(".note", {0, 1, 0}, %{"color" => {0.0, 0.0, 1.0}})
    ]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.color == {0.0, 0.0, 1.0}
    assert computed.font_weight == :bold
  end

  test "embedded <style> rules beat opts[:css] rules at equal specificity" do
    dom = [%HTML.Element{tag: "p", attrs: %{}, children: []}]
    external = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]
    embedded = [rule("p", {0, 0, 1}, %{"color" => {0.0, 1.0, 0.0}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, external, embedded)
    assert computed.color == {0.0, 1.0, 0.0}
  end

  test "inherits color from parent when a child doesn't set it" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [%HTML.Element{tag: "span", attrs: %{}, children: []}]
      }
    ]

    rules = [rule("div", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{computed: parent_computed, children: [%Node{computed: child_computed}]}] =
             Cascade.build(dom, rules, [])

    assert parent_computed.color == {1.0, 0.0, 0.0}
    assert child_computed.color == {1.0, 0.0, 0.0}
  end

  test "em resolves against the node's own resolved font-size, which may come from its parent" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [%HTML.Element{tag: "span", attrs: %{}, children: []}]
      }
    ]

    rules = [
      rule("div", {0, 0, 1}, %{"font-size" => {:length, 20.0, :pt}}),
      rule("span", {0, 0, 1}, %{"margin-top" => {:length, 2.0, :em}})
    ]

    assert [%Node{children: [%Node{computed: child_computed}]}] = Cascade.build(dom, rules, [])
    assert child_computed.font_size == 20.0
    assert child_computed.margin.top == 40.0
  end

  test "% stays symbolic instead of being resolved" do
    dom = [%HTML.Element{tag: "div", attrs: %{}, children: []}]
    rules = [rule("div", {0, 0, 1}, %{"margin-left" => {:length, 50.0, :percent}})]

    assert [%Node{computed: computed}] = Cascade.build(dom, rules, [])
    assert computed.margin.left == {:percent, 50.0}
  end

  test "line-height inherits the specified multiplier, not the parent's resolved points" do
    dom = [
      %HTML.Element{
        tag: "div",
        attrs: %{},
        children: [
          %HTML.Element{
            tag: "span",
            attrs: %{},
            children: []
          }
        ]
      }
    ]

    rules = [
      rule("div", {0, 0, 1}, %{"line-height" => {:line_height, :multiplier, 1.5}, "font-size" => {:length, 10.0, :pt}}),
      rule("span", {0, 0, 1}, %{"font-size" => {:length, 20.0, :pt}})
    ]

    assert [%Node{computed: parent_computed, children: [%Node{computed: child_computed}]}] =
             Cascade.build(dom, rules, [])

    assert parent_computed.line_height == 15.0
    assert child_computed.line_height == 30.0
  end

  test "a bare fragment with multiple top-level siblings has no common root" do
    dom = [
      %HTML.Element{tag: "h1", attrs: %{}, children: []},
      %HTML.Text{content: "hello"}
    ]

    assert [%Node{}, %Text{content: "hello"}] = Cascade.build(dom, [], [])
  end

  test "a text node carries its parent's inherited computed values" do
    dom = [
      %HTML.Element{
        tag: "p",
        attrs: %{},
        children: [%HTML.Text{content: "hi"}]
      }
    ]

    rules = [rule("p", {0, 0, 1}, %{"color" => {1.0, 0.0, 0.0}})]

    assert [%Node{children: [%Text{content: "hi", computed: text_computed}]}] = Cascade.build(dom, rules, [])
    assert text_computed.color == {1.0, 0.0, 0.0}
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/style/cascade_test.exs`
Expected: FAIL — `Press.Style.Cascade` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule Press.Style.Cascade do
  @moduledoc """
  Builds the styled tree: matches CSS rules against the DOM, resolves
  the cascade (per property, ordered by origin + specificity + source
  index), applies inheritance, and resolves units to points — except
  `%`, which stays symbolic (`{:percent, n}`) for Layout to resolve
  against the actual containing block width it computes. See
  `docs/superpowers/specs/2026-07-24-css-parser-cascade-design.md` for
  the full algorithm.
  """

  alias Press.CSS.{DefaultStylesheet, Selector}
  alias Press.HTML
  alias Press.Style.{Node, Text}

  @initial %{
    color: {0.0, 0.0, 0.0},
    font_family: :helvetica,
    font_weight: :normal,
    font_style: :normal,
    text_align: :left,
    list_style_type: :disc,
    list_style_position: :outside
  }

  @initial_font_size 12.0
  @initial_line_height {:line_height, :multiplier, 1.2}

  @keyword_inheritable [
    {:font_family, "font-family"},
    {:font_weight, "font-weight"},
    {:font_style, "font-style"},
    {:text_align, "text-align"},
    {:list_style_type, "list-style-type"},
    {:list_style_position, "list-style-position"}
  ]

  @spec build([HTML.Element.t() | HTML.Text.t()], [Press.CSS.Rule.t()], [Press.CSS.Rule.t()]) ::
          [Node.t() | Text.t()]
  def build(dom, external_rules, embedded_rules) do
    tagged_rules =
      tag_origin(DefaultStylesheet.rules(), 0) ++
        tag_origin(external_rules, 1) ++
        tag_origin(embedded_rules, 2)

    root_context = %{
      ancestors: [],
      inherited: @initial,
      font_size: @initial_font_size,
      line_height_specified: @initial_line_height,
      root_font_size: @initial_font_size
    }

    build_nodes(dom, tagged_rules, root_context)
  end

  defp tag_origin(rules, origin), do: Enum.map(rules, &{origin, &1})

  defp build_nodes(nodes, tagged_rules, context) do
    Enum.map(nodes, &build_node(&1, tagged_rules, context))
  end

  defp build_node(%HTML.Text{content: content}, _tagged_rules, context) do
    computed =
      context.inherited
      |> Map.put(:font_size, context.font_size)
      |> Map.put(
        :line_height,
        resolve_length(context.line_height_specified, context.font_size, context.root_font_size)
      )

    %Text{content: content, computed: computed}
  end

  defp build_node(%HTML.Element{} = element, tagged_rules, context) do
    specified = collect_specified(tagged_rules, element, context.ancestors)

    font_size = resolve_font_size(specified, context)
    line_height_specified = Map.get(specified, "line-height", context.line_height_specified)
    color = Map.get(specified, "color", context.inherited.color)

    keyword_computed =
      Enum.reduce(@keyword_inheritable, %{}, fn {key, prop}, acc ->
        Map.put(acc, key, Map.get(specified, prop, Map.fetch!(context.inherited, key)))
      end)

    computed =
      keyword_computed
      |> Map.put(:color, color)
      |> Map.put(:font_size, font_size)
      |> Map.put(
        :line_height,
        resolve_length(line_height_specified, font_size, context.root_font_size)
      )
      |> Map.put(:margin, regroup_box("margin", specified, font_size, context.root_font_size, &resolve_side/3))
      |> Map.put(:padding, regroup_box("padding", specified, font_size, context.root_font_size, &resolve_side/3))
      |> Map.put(
        :border_width,
        regroup_box("border-width", specified, font_size, context.root_font_size, &resolve_side/3)
      )
      |> Map.put(
        :border_color,
        regroup_box("border-color", specified, font_size, context.root_font_size, fn v, _fs, _r -> v end)
      )
      |> Map.put(
        :border_style,
        regroup_box("border-style", specified, font_size, context.root_font_size, fn v, _fs, _r -> v end)
      )
      |> Map.put(:width, resolve_dimension(Map.get(specified, "width"), font_size, context.root_font_size))
      |> Map.put(:height, resolve_dimension(Map.get(specified, "height"), font_size, context.root_font_size))
      |> Map.put(:background_color, Map.get(specified, "background-color"))

    inherited_keys = Enum.map(@keyword_inheritable, fn {key, _prop} -> key end)
    child_inherited = computed |> Map.take(inherited_keys) |> Map.put(:color, color)

    child_context = %{
      ancestors: [element | context.ancestors],
      inherited: child_inherited,
      font_size: font_size,
      line_height_specified: line_height_specified,
      root_font_size: context.root_font_size
    }

    %Node{
      element: element,
      computed: computed,
      children: build_nodes(element.children, tagged_rules, child_context)
    }
  end

  defp collect_specified(tagged_rules, element, ancestors) do
    tagged_rules
    |> Enum.filter(fn {_origin, rule} -> Selector.matches?(rule.selector, element, ancestors) end)
    |> Enum.sort_by(fn {origin, rule} -> {origin, rule.specificity, rule.source_index} end)
    |> Enum.reduce(%{}, fn {_origin, rule}, acc -> Map.merge(acc, rule.declarations) end)
  end

  defp resolve_font_size(specified, context) do
    case Map.get(specified, "font-size") do
      nil -> context.font_size
      {:length, n, :percent} -> n / 100.0 * context.font_size
      term -> resolve_absolute_em_rem(term, context.font_size, context.root_font_size)
    end
  end

  defp regroup_box(prefix, specified, font_size, root, resolver) do
    %{
      top: resolver.(Map.get(specified, "#{prefix}-top"), font_size, root),
      right: resolver.(Map.get(specified, "#{prefix}-right"), font_size, root),
      bottom: resolver.(Map.get(specified, "#{prefix}-bottom"), font_size, root),
      left: resolver.(Map.get(specified, "#{prefix}-left"), font_size, root)
    }
  end

  defp resolve_side(nil, _font_size, _root), do: 0.0
  defp resolve_side({:length, n, :percent}, _font_size, _root), do: {:percent, n}
  defp resolve_side(term, font_size, root), do: resolve_absolute_em_rem(term, font_size, root)

  defp resolve_dimension(nil, _font_size, _root), do: :auto
  defp resolve_dimension({:length, n, :percent}, _font_size, _root), do: {:percent, n}
  defp resolve_dimension(term, font_size, root), do: resolve_absolute_em_rem(term, font_size, root)

  defp resolve_length({:line_height, :multiplier, n}, font_size, _root), do: n * font_size
  defp resolve_length(term, font_size, root), do: resolve_absolute_em_rem(term, font_size, root)

  defp resolve_absolute_em_rem({:length, n, :em}, font_size, _root), do: n * font_size
  defp resolve_absolute_em_rem({:length, n, :rem}, _font_size, root), do: n * root
  defp resolve_absolute_em_rem({:length, n, :mm}, _fs, _r), do: n * 72.0 / 25.4
  defp resolve_absolute_em_rem({:length, n, :cm}, _fs, _r), do: n * 72.0 / 2.54
  defp resolve_absolute_em_rem({:length, n, :in}, _fs, _r), do: n * 72.0
  defp resolve_absolute_em_rem({:length, n, :pt}, _fs, _r), do: n * 1.0
  defp resolve_absolute_em_rem({:length, n, :px}, _fs, _r), do: n * 0.75
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/style/cascade_test.exs`
Expected: PASS (9 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/style/cascade.ex test/press/style/cascade_test.exs
git commit -m "Add Press.Style.Cascade.build/3"
```

---

## Task 8: `Press.Style.Cascade.page_config/2` — `@page` resolution

**Files:**
- Modify: `lib/press/style/cascade.ex` (append `page_config/2` and its
  private helpers — same module as Task 7, a separate function, not a
  new pipeline stage)
- Modify: `test/press/style/cascade_test.exs` (append a `describe
  "page_config/2"` block)

Resolves `size`/`margin` from `page_rules`, folding by appearance order
(no specificity), with the A4/20mm defaults.

- [ ] **Step 1: Write the failing tests**

Append to `test/press/style/cascade_test.exs` (add `alias Press.CSS.PageRule` next to the existing aliases):

```elixir
  describe "page_config/2" do
    test "defaults to A4 with 20mm margins when no @page rules are given" do
      config = Cascade.page_config([], [])

      assert_in_delta elem(config.size, 0), 595.28, 0.1
      assert_in_delta elem(config.size, 1), 841.89, 0.1
      assert_in_delta config.margin.top, 56.69, 0.1
      assert_in_delta config.margin.right, 56.69, 0.1
    end

    test "uses the last rule to set each of size/margin, across origins" do
      external = [%PageRule{declarations: %{"size" => :letter}, source_index: 0}]

      embedded_margin = %{
        top: {:length, 10.0, :mm},
        right: {:length, 10.0, :mm},
        bottom: {:length, 10.0, :mm},
        left: {:length, 10.0, :mm}
      }

      embedded = [%PageRule{declarations: %{"margin" => embedded_margin}, source_index: 0}]

      config = Cascade.page_config(external, embedded)

      assert config.size == {612.0, 792.0}
      assert_in_delta config.margin.top, 28.35, 0.1
    end

    test "resolves a custom two-length size" do
      custom = {:custom, {:length, 210.0, :mm}, {:length, 297.0, :mm}}
      external = [%PageRule{declarations: %{"size" => custom}, source_index: 0}]

      config = Cascade.page_config(external, [])

      assert_in_delta elem(config.size, 0), 595.28, 0.1
      assert_in_delta elem(config.size, 1), 841.89, 0.1
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/style/cascade_test.exs`
Expected: FAIL — `Press.Style.Cascade.page_config/2` is undefined.

- [ ] **Step 3: Write the implementation**

Append to `lib/press/style/cascade.ex`, inside `defmodule Press.Style.Cascade do ... end`:

```elixir
  @mm_to_pt 72.0 / 25.4

  @spec page_config([Press.CSS.PageRule.t()], [Press.CSS.PageRule.t()]) :: %{
          size: {float(), float()},
          margin: %{top: float(), right: float(), bottom: float(), left: float()}
        }
  def page_config(external_page_rules, embedded_page_rules) do
    all = DefaultStylesheet.page_rules() ++ external_page_rules ++ embedded_page_rules

    size = all |> Enum.map(&Map.get(&1.declarations, "size")) |> Enum.reject(&is_nil/1) |> List.last()
    margin = all |> Enum.map(&Map.get(&1.declarations, "margin")) |> Enum.reject(&is_nil/1) |> List.last()

    %{size: resolve_page_size(size), margin: resolve_page_margin(margin)}
  end

  defp resolve_page_size(nil), do: {595.28, 841.89}
  defp resolve_page_size(:a4), do: {595.28, 841.89}
  defp resolve_page_size(:letter), do: {612.0, 792.0}
  defp resolve_page_size(:legal), do: {612.0, 1008.0}

  defp resolve_page_size({:custom, w, h}) do
    case {resolve_page_length(w), resolve_page_length(h)} do
      {nil, _} -> resolve_page_size(nil)
      {_, nil} -> resolve_page_size(nil)
      {wv, hv} -> {wv, hv}
    end
  end

  defp resolve_page_margin(nil), do: default_page_margin()

  defp resolve_page_margin(%{top: t, right: r, bottom: b, left: l}) do
    with tv when not is_nil(tv) <- resolve_page_length(t),
         rv when not is_nil(rv) <- resolve_page_length(r),
         bv when not is_nil(bv) <- resolve_page_length(b),
         lv when not is_nil(lv) <- resolve_page_length(l) do
      %{top: tv, right: rv, bottom: bv, left: lv}
    else
      nil -> default_page_margin()
    end
  end

  defp default_page_margin do
    mm20 = 20 * @mm_to_pt
    %{top: mm20, right: mm20, bottom: mm20, left: mm20}
  end

  defp resolve_page_length({:length, _n, :percent}), do: nil
  defp resolve_page_length({:length, _n, unit}) when unit in [:em, :rem], do: nil
  defp resolve_page_length({:length, n, :mm}), do: n * @mm_to_pt
  defp resolve_page_length({:length, n, :cm}), do: n * 72.0 / 2.54
  defp resolve_page_length({:length, n, :in}), do: n * 72.0
  defp resolve_page_length({:length, n, :pt}), do: n * 1.0
  defp resolve_page_length({:length, n, :px}), do: n * 0.75
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/style/cascade_test.exs`
Expected: PASS (12 tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add lib/press/style/cascade.ex test/press/style/cascade_test.exs
git commit -m "Add Press.Style.Cascade.page_config/2 for @page resolution"
```

---

## Task 9: End-to-end integration test

**Files:**
- Test: `test/press/style/integration_test.exs`

Real HTML+CSS through `Press.HTML.Parser` + `Press.CSS.Parser` +
`Press.Style.Cascade.build/3` together — combining the UA stylesheet,
an external stylesheet, and an embedded `<style>` block, confirming all
three stages of this phase work together. This is the acceptance test
for Phase 3.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Press.Style.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Element
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Style.{Cascade, Node}

  test "parses and cascades a fragment combining the UA stylesheet, an external stylesheet, and embedded <style>" do
    html = """
    <style>.total { color: red; }</style>
    <h1>Invoice #123</h1>
    <p class="total">Total: 100</p>
    """

    external_css = "p { font-size: 14px; }"

    dom = HTMLParser.parse(html)
    {_ext_page_rules, external_rules} = CSSParser.parse(external_css)

    embedded_css =
      dom
      |> find_dom("style")
      |> Enum.map_join("\n", fn %{children: [%Press.HTML.Text{content: content}]} -> content end)

    {_emb_page_rules, embedded_rules} = CSSParser.parse(embedded_css)

    styled = Cascade.build(dom, external_rules, embedded_rules)

    [h1] = find_styled(styled, "h1")
    assert h1.computed.font_size == 24.0

    [p] = find_styled(styled, "p")
    assert_in_delta p.computed.font_size, 10.5, 0.01
    assert p.computed.color == {1.0, 0.0, 0.0}
  end

  # Pre-cascade: filters Press.HTML.Element nodes from Press.HTML.Parser's output.
  defp find_dom(nodes, tag) do
    Enum.filter(nodes, &match?(%Element{tag: ^tag}, &1))
  end

  # Post-cascade: filters Press.Style.Node nodes from Press.Style.Cascade.build/3's output.
  defp find_styled(nodes, tag) do
    Enum.filter(nodes, &match?(%Node{element: %{tag: ^tag}}, &1))
  end
end
```

- [ ] **Step 2: Run the test**

Run: `mix test test/press/style/integration_test.exs`
Expected: PASS immediately — it only exercises the already-built public
API of Tasks 1-8. If it fails, that's a real bug in an earlier task;
fix the relevant module (not this test).

- [ ] **Step 3: Run the full suite**

Run: `mix test`
Expected: all tests passing — Phase 1 + Phase 2's ~74 tests plus this
phase's new ones, 0 failures.

- [ ] **Step 4: Record two follow-ups in `TODO.md` and commit**

```markdown
- Layout (Phase 4) must skip non-visual elements (`style`, `link`,
  `meta`, `head`) when walking the styled tree — `Press.Style.Cascade`
  cascades them like any other element (harmless: they just get
  default computed values with no CSS rules matching in practice), but
  they should never be rendered.
```

```bash
git add test/press/style/integration_test.exs TODO.md
git commit -m "Add end-to-end integration test for CSS parser + cascade"
```

---

## Definition of Done

- [ ] All tasks above complete, all tests passing (`mix test`).
- [ ] `mix format --check-formatted` clean.
- [ ] `docs/superpowers/plans/2026-07-28-css-parser-cascade.md` (this
      file) has every checkbox ticked.
- [ ] Next phase (Phase 4 — Layout, per
      `docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`)
      gets its own spec/plan when it's time to start it.
