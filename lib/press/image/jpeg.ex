defmodule Press.Image.JPEG do
  @moduledoc false

  alias Press.Image

  @sof_markers [
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF
  ]

  @doc """
  Parses a JPEG binary, extracting width, height, and color space from SOF markers.
  """
  @spec parse(binary()) :: {:ok, Image.t()} | {:error, :invalid_jpeg}
  def parse(<<0xFF, 0xD8, rest::binary>> = full_data) do
    case scan_markers(rest) do
      {:ok, width, height, color_space} ->
        {:ok,
         %Image{
           format: :jpeg,
           width: width,
           height: height,
           color_space: color_space,
           data: full_data
         }}

      :error ->
        {:error, :invalid_jpeg}
    end
  end

  def parse(_), do: {:error, :invalid_jpeg}

  defp scan_markers(
         <<0xFF, marker, _len::16, _precision, height::16, width::16, components, _rest::binary>>
       )
       when marker in @sof_markers do
    color_space = if components == 1, do: :gray, else: :rgb
    {:ok, width, height, color_space}
  end

  defp scan_markers(<<0xFF, 0xD9, _rest::binary>>), do: :error

  defp scan_markers(<<0xFF, marker, len::16, rest::binary>>)
       when marker not in [0x00, 0xFF, 0xD8, 0xD9] do
    payload_len = len - 2

    if byte_size(rest) >= payload_len do
      <<_payload::binary-size(payload_len), next::binary>> = rest
      scan_markers(next)
    else
      :error
    end
  end

  defp scan_markers(<<_byte, rest::binary>>), do: scan_markers(rest)
  defp scan_markers(<<>>), do: :error
end
