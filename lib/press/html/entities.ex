defmodule Press.HTML.Entities do
  @moduledoc false

  @entity_regex ~r/&(amp|lt|gt|quot|apos|#[0-9]+|#[xX][0-9a-fA-F]+);/

  def decode(text) when is_binary(text) do
    Regex.replace(@entity_regex, text, &decode_match/2)
  end

  defp decode_match(_whole, "amp"), do: "&"
  defp decode_match(_whole, "lt"), do: "<"
  defp decode_match(_whole, "gt"), do: ">"
  defp decode_match(_whole, "quot"), do: "\""
  defp decode_match(_whole, "apos"), do: "'"

  defp decode_match(whole, "#" <> rest) do
    {digits, base} =
      case rest do
        "x" <> hex -> {hex, 16}
        "X" <> hex -> {hex, 16}
        dec -> {dec, 10}
      end

    case Integer.parse(digits, base) do
      {codepoint, ""} when codepoint in 0x00..0xD7FF or codepoint in 0xE000..0x10FFFF ->
        <<codepoint::utf8>>

      _ ->
        whole
    end
  end
end
