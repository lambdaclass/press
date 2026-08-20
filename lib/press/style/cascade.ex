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
      |> Map.put(
        :margin,
        regroup_box("margin", specified, font_size, context.root_font_size, &resolve_side/3)
      )
      |> Map.put(
        :padding,
        regroup_box("padding", specified, font_size, context.root_font_size, &resolve_side/3)
      )
      |> Map.put(
        :border_width,
        regroup_box(
          "border-width",
          specified,
          font_size,
          context.root_font_size,
          &resolve_side/3
        )
      )
      |> Map.put(
        :border_color,
        regroup_box(
          "border-color",
          specified,
          font_size,
          context.root_font_size,
          fn v, _fs, _r -> v end
        )
      )
      |> Map.put(
        :border_style,
        regroup_box(
          "border-style",
          specified,
          font_size,
          context.root_font_size,
          fn v, _fs, _r -> v end
        )
      )
      |> Map.put(
        :width,
        resolve_dimension(Map.get(specified, "width"), font_size, context.root_font_size)
      )
      |> Map.put(
        :height,
        resolve_dimension(Map.get(specified, "height"), font_size, context.root_font_size)
      )
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

  defp resolve_dimension(term, font_size, root),
    do: resolve_absolute_em_rem(term, font_size, root)

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
