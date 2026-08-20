defmodule Press.Image.Parser do
  @moduledoc false

  alias Press.Image
  alias Press.Image.{JPEG, PNG}

  @doc """
  Loads and parses an image from a Data URI or an images lookup map.
  """
  @spec load(String.t(), map()) :: {:ok, Image.t()} | {:error, term()}
  def load(src, images_map) when is_binary(src) and is_map(images_map) do
    cond do
      String.starts_with?(src, "data:") ->
        load_data_uri(src)

      Map.has_key?(images_map, src) ->
        binary_data = Map.fetch!(images_map, src)
        parse_binary(binary_data)

      true ->
        {:error, {:image_not_found, src}}
    end
  end

  defp load_data_uri(uri) do
    case Regex.run(~r/^data:image\/(png|jpeg|jpg);base64,(.*)$/s, uri) do
      [_, _type, base64_payload] ->
        clean_b64 = String.replace(base64_payload, ~r/\s+/, "")

        case Base.decode64(clean_b64) do
          {:ok, binary} -> parse_binary(binary)
          :error -> {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_data_uri}
    end
  end

  defp parse_binary(<<0xFF, 0xD8, _rest::binary>> = binary), do: JPEG.parse(binary)

  defp parse_binary(<<137, 80, 78, 71, 13, 10, 26, 10, _rest::binary>> = binary),
    do: PNG.parse(binary)

  defp parse_binary(_), do: {:error, :unsupported_format}
end
