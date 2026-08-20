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
    "text-align" => [:left, :right, :center, :justify],
    "vertical-align" => [:top, :middle, :bottom, :baseline],
    "text-transform" => [:uppercase, :lowercase, :capitalize, :none],
    "list-style-type" => [:disc, :decimal, :none],
    "list-style-position" => [:outside, :inside],
    "box-sizing" => [:"content-box", :"border-box"],
    "border-collapse" => [:collapse, :separate],
    "page-break-before" => [:auto, :always],
    "page-break-after" => [:auto, :always]
  }

  @side_length_properties %{
    "margin-top" => "margin-top",
    "margin-right" => "margin-right",
    "margin-bottom" => "margin-bottom",
    "margin-left" => "margin-left",
    "padding-top" => "padding-top",
    "padding-right" => "padding-right",
    "padding-bottom" => "padding-bottom",
    "padding-left" => "padding-left",
    "border-top-width" => "border-width-top",
    "border-right-width" => "border-width-right",
    "border-bottom-width" => "border-width-bottom",
    "border-left-width" => "border-width-left",
    "border-width-top" => "border-width-top",
    "border-width-right" => "border-width-right",
    "border-width-bottom" => "border-width-bottom",
    "border-width-left" => "border-width-left"
  }

  @side_color_properties %{
    "border-top-color" => "border-color-top",
    "border-right-color" => "border-color-right",
    "border-bottom-color" => "border-color-bottom",
    "border-left-color" => "border-color-left",
    "border-color-top" => "border-color-top",
    "border-color-right" => "border-color-right",
    "border-color-bottom" => "border-color-bottom",
    "border-color-left" => "border-color-left"
  }

  @font_family_aliases %{
    "helvetica" => :helvetica,
    "arial" => :helvetica,
    "sans-serif" => :helvetica,
    "ui-sans-serif" => :helvetica,
    "system-ui" => :helvetica,
    "times" => :times,
    "times new roman" => :times,
    "serif" => :times,
    "courier" => :courier,
    "courier new" => :courier,
    "monospace" => :courier,
    "ui-monospace" => :courier,
    "sfmono-regular" => :courier,
    "menlo" => :courier,
    "monaco" => :courier,
    "consolas" => :courier
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

  defp split_blocks(css) do
    tokenize_blocks(css, [], "")
  end

  defp tokenize_blocks(<<>>, acc, _header), do: Enum.reverse(acc)

  defp tokenize_blocks(<<";", rest::binary>>, acc, _header) do
    tokenize_blocks(rest, acc, "")
  end

  defp tokenize_blocks(<<"{", rest::binary>>, acc, header) do
    case extract_balanced_body(rest, 1, <<>>) do
      {:ok, body, remaining} ->
        trimmed_header = String.trim(header)

        cond do
          String.starts_with?(trimmed_header, "@layer") or
            String.starts_with?(trimmed_header, "@media") or
              String.starts_with?(trimmed_header, "@supports") ->
            nested = split_blocks(body)
            tokenize_blocks(remaining, nested ++ acc, "")

          String.starts_with?(trimmed_header, "@keyframes") or
            String.starts_with?(trimmed_header, "@property") or
              String.starts_with?(trimmed_header, "@font-face") ->
            tokenize_blocks(remaining, acc, "")

          true ->
            tokenize_blocks(remaining, [{trimmed_header, body} | acc], "")
        end

      :error ->
        Enum.reverse(acc)
    end
  end

  defp tokenize_blocks(<<char, rest::binary>>, acc, header) do
    tokenize_blocks(rest, acc, header <> <<char>>)
  end

  defp extract_balanced_body(<<>>, _depth, _acc), do: :error

  defp extract_balanced_body(<<"{", rest::binary>>, depth, acc) do
    extract_balanced_body(rest, depth + 1, acc <> "{")
  end

  defp extract_balanced_body(<<"}", rest::binary>>, 1, acc) do
    {:ok, acc, rest}
  end

  defp extract_balanced_body(<<"}", rest::binary>>, depth, acc) do
    extract_balanced_body(rest, depth - 1, acc <> "}")
  end

  defp extract_balanced_body(<<char, rest::binary>>, depth, acc) do
    extract_balanced_body(rest, depth, acc <> <<char>>)
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
        |> split_balanced_commas()
        |> Enum.map(&Selector.parse/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn compounds ->
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

  defp split_balanced_commas(text) do
    tokenize_commas(text, 0, 0, <<>>, [])
  end

  defp tokenize_commas(<<>>, _paren, _bracket, acc, list) do
    Enum.reverse([String.trim(acc) | list]) |> Enum.reject(&(&1 == ""))
  end

  defp tokenize_commas(<<",", rest::binary>>, 0, 0, acc, list) do
    tokenize_commas(rest, 0, 0, <<>>, [String.trim(acc) | list])
  end

  defp tokenize_commas(<<"(", rest::binary>>, paren, bracket, acc, list) do
    tokenize_commas(rest, paren + 1, bracket, acc <> "(", list)
  end

  defp tokenize_commas(<<")", rest::binary>>, paren, bracket, acc, list) do
    tokenize_commas(rest, max(0, paren - 1), bracket, acc <> ")", list)
  end

  defp tokenize_commas(<<"[", rest::binary>>, paren, bracket, acc, list) do
    tokenize_commas(rest, paren, bracket + 1, acc <> "[", list)
  end

  defp tokenize_commas(<<"]", rest::binary>>, paren, bracket, acc, list) do
    tokenize_commas(rest, paren, max(0, bracket - 1), acc <> "]", list)
  end

  defp tokenize_commas(<<char, rest::binary>>, paren, bracket, acc, list) do
    tokenize_commas(rest, paren, bracket, acc <> <<char>>, list)
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
      {prop |> String.trim() |> String.downcase(),
       value |> String.trim() |> resolve_tailwind_var()}
    end)
  end

  defp resolve_tailwind_var(value) do
    case value do
      "var(--text-xs)" ->
        "0.75rem"

      "var(--text-sm)" ->
        "0.875rem"

      "var(--text-base)" ->
        "1rem"

      "var(--text-lg)" ->
        "1.125rem"

      "var(--text-xl)" ->
        "1.25rem"

      "var(--text-2xl)" ->
        "1.5rem"

      "var(--text-3xl)" ->
        "1.875rem"

      "var(--text-4xl)" ->
        "2.25rem"

      "var(--font-weight-bold)" ->
        "bold"

      "var(--font-weight-semibold)" ->
        "bold"

      "var(--font-weight-normal)" ->
        "normal"

      "var(--font-mono)" ->
        "courier"

      "var(--font-sans)" ->
        "helvetica"

      "var(--font-serif)" ->
        "times"

      _ ->
        if String.starts_with?(value, "calc(") do
          expand_calc_spacing(value)
        else
          value
        end
    end
  end

  defp expand_calc_spacing(value) do
    case Regex.run(~r/calc\(\s*var\(--spacing\)\s*\*\s*([\d\.]+)\s*\)/, value) do
      [_, n] ->
        case Float.parse(n) do
          {f, ""} -> "#{f * 0.25}rem"
          _ -> value
        end

      nil ->
        case Regex.run(~r/calc\(\s*([\d\.]+)\s*\*\s*var\(--spacing\)\s*\)/, value) do
          [_, n] ->
            case Float.parse(n) do
              {f, ""} -> "#{f * 0.25}rem"
              _ -> value
            end

          nil ->
            value
        end
    end
  end

  defp parse_declaration("border", value), do: Shorthand.expand_border(value)

  defp parse_declaration("border-top", value), do: expand_directional_border("top", value)
  defp parse_declaration("border-right", value), do: expand_directional_border("right", value)
  defp parse_declaration("border-bottom", value), do: expand_directional_border("bottom", value)
  defp parse_declaration("border-left", value), do: expand_directional_border("left", value)

  defp parse_declaration("border-style", value) do
    # Not in @box_shorthand_properties: a closure (as opposed to a
    # remote function capture like &Value.parse_length/1) can't be
    # stored in a module attribute — Elixir can't escape it into the
    # BEAM constant pool at compile time. Handled as its own clause
    # instead.
    Shorthand.expand_box("border-style", value, fn v -> Value.parse_keyword(v, [:solid]) end)
  end

  defp parse_declaration("padding-inline", value) do
    with {:ok, v} <- Value.parse_length(value) do
      {:ok, %{"padding-left" => v, "padding-right" => v}}
    end
  end

  defp parse_declaration("padding-block", value) do
    with {:ok, v} <- Value.parse_length(value) do
      {:ok, %{"padding-top" => v, "padding-bottom" => v}}
    end
  end

  defp parse_declaration("margin-inline", value) do
    with {:ok, v} <- Value.parse_length(value) do
      {:ok, %{"margin-left" => v, "margin-right" => v}}
    end
  end

  defp parse_declaration("margin-block", value) do
    with {:ok, v} <- Value.parse_length(value) do
      {:ok, %{"margin-top" => v, "margin-bottom" => v}}
    end
  end

  defp parse_declaration("font-family", value) do
    alias_name =
      value
      |> String.split(",")
      |> Enum.find_value(:helvetica, fn name ->
        trimmed =
          name |> String.trim() |> String.trim("\"") |> String.trim("'") |> String.downcase()

        Map.get(@font_family_aliases, trimmed)
      end)

    {:ok, %{"font-family" => alias_name}}
  end

  defp parse_declaration("line-height", value) do
    with {:ok, v} <- Value.parse_line_height(value), do: {:ok, %{"line-height" => v}}
  end

  defp parse_declaration(property, value) do
    cond do
      parse_fun = Map.get(@box_shorthand_properties, property) ->
        Shorthand.expand_box(property, value, parse_fun)

      norm_prop = Map.get(@side_length_properties, property) ->
        with {:ok, v} <- Value.parse_length(value), do: {:ok, %{norm_prop => v}}

      norm_color = Map.get(@side_color_properties, property) ->
        with {:ok, v} <- Value.parse_color(value), do: {:ok, %{norm_color => v}}

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

  defp expand_directional_border(side, value) do
    with {:ok, map} <- Shorthand.expand_border(value) do
      declarations =
        %{
          "border-width-#{side}" => Map.get(map, "border-width-top"),
          "border-color-#{side}" => Map.get(map, "border-color-top"),
          "border-style-#{side}" => Map.get(map, "border-style-top")
        }
        |> Enum.reject(fn {_, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, declarations}
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
