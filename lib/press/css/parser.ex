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

  @doc """
  Parses a CSS declarations string (e.g. from an inline `style="..."` attribute)
  into a map of property-value pairs.
  """
  def parse_declarations(body) do
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
    |> Enum.map(fn [prop, value] ->
      {prop |> String.trim() |> String.downcase(), String.trim(value)}
    end)
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
