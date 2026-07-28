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
