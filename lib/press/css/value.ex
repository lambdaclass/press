defmodule Press.CSS.Value do
  @moduledoc false

  @named_colors %{
    "black" => "000000",
    "white" => "FFFFFF",
    "red" => "FF0000",
    "green" => "008000",
    "blue" => "0000FF",
    "yellow" => "FFFF00",
    "orange" => "FFA500",
    "purple" => "800080",
    "pink" => "FFC0CB",
    "brown" => "A52A2A",
    "gray" => "808080",
    "grey" => "808080",
    "silver" => "C0C0C0",
    "gold" => "FFD700",
    "maroon" => "800000",
    "navy" => "000080",
    "teal" => "008080",
    "olive" => "808000",
    "lime" => "00FF00",
    "aqua" => "00FFFF",
    "cyan" => "00FFFF",
    "fuchsia" => "FF00FF",
    "magenta" => "FF00FF",
    "indigo" => "4B0082",
    "violet" => "EE82EE",
    "turquoise" => "40E0D0",
    "coral" => "FF7F50",
    "salmon" => "FA8072",
    "khaki" => "F0E68C",
    "tan" => "D2B48C",
    "beige" => "F5F5DC",
    "ivory" => "FFFFF0",
    "lavender" => "E6E6FA",
    "plum" => "DDA0DD",
    "orchid" => "DA70D6",
    "chocolate" => "D2691E",
    "crimson" => "DC143C",
    "skyblue" => "87CEEB",
    "steelblue" => "4682B4",
    "royalblue" => "4169E1",
    "forestgreen" => "228B22",
    "seagreen" => "2E8B57",
    "springgreen" => "00FF7F",
    "yellowgreen" => "9ACD32",
    "olivedrab" => "6B8E23",
    "darkgreen" => "006400",
    "darkblue" => "00008B",
    "darkred" => "8B0000",
    "lightblue" => "ADD8E6",
    "lightgreen" => "90EE90",
    "lightgray" => "D3D3D3",
    "lightgrey" => "D3D3D3",
    "lightyellow" => "FFFFE0",
    "lightpink" => "FFB6C1",
    "darkgray" => "A9A9A9",
    "dimgray" => "696969",
    "slategray" => "708090",
    "whitesmoke" => "F5F5F5"
  }

  @length_regex ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)$/
  @zero_regex ~r/^0(?:\.0+)?$/
  @rgb_regex ~r/^rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)$/
  @multiplier_regex ~r/^-?\d+(?:\.\d+)?$/
  @absolute_length_regex ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem)$/

  @oklch_regex ~r/^oklch\(\s*([\d\.]+%?)\s+([\d\.]+)\s+([\d\.]+)\s*\)$/
  @var_base_100_regex ~r/^var\(--color-base-100/
  @var_base_200_regex ~r/^var\(--color-base-200/
  @var_base_300_regex ~r/^var\(--color-base-300/
  @var_base_content_regex ~r/^var\(--color-base-content/
  @var_primary_regex ~r/^var\(--color-primary/

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
        {:ok,
         {String.to_integer(r) / 255.0, String.to_integer(g) / 255.0,
          String.to_integer(b) / 255.0}}

      nil ->
        case parse_oklch(str) do
          {:ok, rgb} ->
            {:ok, rgb}

          :error ->
            case parse_var(str) do
              {:ok, rgb} ->
                {:ok, rgb}

              :error ->
                case Map.fetch(@named_colors, String.downcase(str)) do
                  {:ok, hex} -> parse_hex_color("#" <> hex)
                  :error -> :error
                end
            end
        end
    end
  end

  defp parse_oklch(str) do
    case Regex.run(@oklch_regex, str) do
      [_, l_str, c_str, h_str] ->
        l =
          if String.ends_with?(l_str, "%") do
            parse_number(String.trim_trailing(l_str, "%")) / 100.0
          else
            parse_number(l_str)
          end

        c = parse_number(c_str)
        h = parse_number(h_str)
        {:ok, oklch_to_rgb(l, c, h)}

      nil ->
        :error
    end
  end

  defp parse_var(str) do
    cond do
      Regex.match?(@var_base_100_regex, str) -> {:ok, {0.98, 0.98, 0.98}}
      Regex.match?(@var_base_200_regex, str) -> {:ok, {0.9472, 0.9472, 0.9502}}
      Regex.match?(@var_base_300_regex, str) -> {:ok, {0.8945, 0.8945, 0.9062}}
      Regex.match?(@var_base_content_regex, str) -> {:ok, {0.15, 0.15, 0.15}}
      Regex.match?(@var_primary_regex, str) -> {:ok, {0.31, 0.27, 0.90}}
      true -> :error
    end
  end

  defp oklch_to_rgb(l, c, h) do
    h_rad = h * :math.pi() / 180.0
    a = c * :math.cos(h_rad)
    b = c * :math.sin(h_rad)

    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b

    l3 = l_ * l_ * l_
    m3 = m_ * m_ * m_
    s3 = s_ * s_ * s_

    r_lin = +4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
    g_lin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
    b_lin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3

    r = linear_to_srgb(r_lin)
    g = linear_to_srgb(g_lin)
    b = linear_to_srgb(b_lin)

    {Float.round(r, 4), Float.round(g, 4), Float.round(b, 4)}
  end

  defp linear_to_srgb(c) do
    clamped = max(0.0, min(1.0, c))

    if clamped <= 0.0031308 do
      12.92 * clamped
    else
      1.055 * :math.pow(clamped, 1.0 / 2.4) - 0.055
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

      String.starts_with?(str, "calc(") ->
        parse_calc_length(str)

      match = Regex.run(@length_regex, str) ->
        [_, number, unit] = match
        {:ok, {:length, parse_number(number), unit_atom(unit)}}

      true ->
        :error
    end
  end

  def parse_calc_length(str) do
    case Regex.run(~r/^calc\(\s*(.*?)\s*\)$/, str) do
      [_, expr] ->
        expr =
          expr
          |> String.replace("var(--spacing)", "0.25rem")

        eval_length_expr(expr)

      nil ->
        :error
    end
  end

  defp eval_length_expr(expr) do
    expr = String.trim(expr)

    cond do
      # multiplication: number_unit * factor
      match =
          Regex.run(
            ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)\s*\*\s*(-?\d+(?:\.\d+)?)$/,
            expr
          ) ->
        [_, num_str, unit, factor_str] = match
        {:ok, {:length, parse_number(num_str) * parse_number(factor_str), unit_atom(unit)}}

      # multiplication: factor * number_unit
      match =
          Regex.run(
            ~r/^(-?\d+(?:\.\d+)?)\s*\*\s*(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)$/,
            expr
          ) ->
        [_, factor_str, num_str, unit] = match
        {:ok, {:length, parse_number(num_str) * parse_number(factor_str), unit_atom(unit)}}

      # division: number_unit / divisor
      match =
          Regex.run(
            ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)\s*\/\s*(-?\d+(?:\.\d+)?)$/,
            expr
          ) ->
        [_, num_str, unit, divisor_str] = match
        d = parse_number(divisor_str)
        if d != 0, do: {:ok, {:length, parse_number(num_str) / d, unit_atom(unit)}}, else: :error

      # addition: n1 unit + n2 unit
      match =
          Regex.run(
            ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)\s*\+\s*(-?\d+(?:\.\d+)?)\2$/,
            expr
          ) ->
        [_, n1_str, unit, n2_str] = match
        {:ok, {:length, parse_number(n1_str) + parse_number(n2_str), unit_atom(unit)}}

      # subtraction: n1 unit - n2 unit
      match =
          Regex.run(
            ~r/^(-?\d+(?:\.\d+)?)(mm|cm|in|pt|px|em|rem|%)\s*-\s*(-?\d+(?:\.\d+)?)\2$/,
            expr
          ) ->
        [_, n1_str, unit, n2_str] = match
        {:ok, {:length, parse_number(n1_str) - parse_number(n2_str), unit_atom(unit)}}

      # plain length inside calc
      match = Regex.run(@length_regex, expr) ->
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
