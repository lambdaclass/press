defmodule Press.Image.PNG do
  @moduledoc false

  import Bitwise
  alias Press.Image

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Parses a PNG binary, unfilters scanlines, separates alpha channels if present,
  and recompresses pixel payloads with :zlib.
  """
  @spec parse(binary()) :: {:ok, Image.t()} | {:error, :invalid_png}
  def parse(@png_signature <> rest) do
    case read_chunks(rest, %{idat: [], plte: nil, trns: nil, ihdr: nil}) do
      {:ok, chunks} ->
        process_png(chunks)

      :error ->
        {:error, :invalid_png}
    end
  end

  def parse(_), do: {:error, :invalid_png}

  defp read_chunks(<<>>, chunks) do
    if chunks.ihdr && chunks.idat != [] do
      {:ok, chunks}
    else
      :error
    end
  end

  defp read_chunks(
         <<len::32, type::binary-size(4), data::binary-size(len), _crc::32, rest::binary>>,
         chunks
       ) do
    new_chunks =
      case type do
        "IHDR" -> %{chunks | ihdr: parse_ihdr(data)}
        "IDAT" -> %{chunks | idat: [data | chunks.idat]}
        "PLTE" -> %{chunks | plte: data}
        "tRNS" -> %{chunks | trns: data}
        "IEND" -> chunks
        _other -> chunks
      end

    if type == "IEND" do
      {:ok, new_chunks}
    else
      read_chunks(rest, new_chunks)
    end
  end

  defp read_chunks(_, _), do: :error

  defp parse_ihdr(
         <<width::32, height::32, bit_depth::8, color_type::8, _comp::8, _filter::8,
           interlace::8>>
       ) do
    %{
      width: width,
      height: height,
      bit_depth: bit_depth,
      color_type: color_type,
      interlace: interlace
    }
  end

  defp parse_ihdr(_), do: nil

  defp process_png(
         %{ihdr: %{width: w, height: h, color_type: color_type, bit_depth: 8, interlace: 0}} =
           chunks
       ) do
    idat_binary = chunks.idat |> Enum.reverse() |> IO.iodata_to_binary()

    case safe_uncompress(idat_binary) do
      {:ok, uncompressed} ->
        bpp = bytes_per_pixel(color_type)
        line_len = w * bpp

        case unfilter_scanlines(uncompressed, h, line_len, bpp, []) do
          {:ok, raw_pixel_data} ->
            build_image(raw_pixel_data, w, h, color_type, chunks)

          :error ->
            {:error, :invalid_png}
        end

      :error ->
        {:error, :invalid_png}
    end
  end

  defp process_png(_), do: {:error, :invalid_png}

  defp safe_uncompress(binary) do
    {:ok, :zlib.uncompress(binary)}
  rescue
    _ -> :error
  end

  defp bytes_per_pixel(0), do: 1
  defp bytes_per_pixel(2), do: 3
  defp bytes_per_pixel(3), do: 1
  defp bytes_per_pixel(4), do: 2
  defp bytes_per_pixel(6), do: 4
  defp bytes_per_pixel(_), do: 1

  defp unfilter_scanlines(<<>>, 0, _line_len, _bpp, acc) do
    {:ok, IO.iodata_to_binary(Enum.reverse(acc))}
  end

  defp unfilter_scanlines(data, remaining_lines, line_len, bpp, acc) when remaining_lines > 0 do
    case data do
      <<filter_type::8, scanline::binary-size(line_len), rest::binary>> ->
        prior_line = List.first(acc) || :binary.copy(<<0>>, line_len)
        unfiltered = unfilter_line(filter_type, scanline, prior_line, bpp)
        unfilter_scanlines(rest, remaining_lines - 1, line_len, bpp, [unfiltered | acc])

      _ ->
        :error
    end
  end

  defp unfilter_scanlines(_, _, _, _, _), do: :error

  defp unfilter_line(0, scanline, _prior, _bpp), do: scanline

  defp unfilter_line(filter_type, scanline, prior, bpp) do
    len = byte_size(scanline)
    unfilter_bytes(scanline, prior, filter_type, bpp, 0, len, <<>>)
  end

  defp unfilter_bytes(_scanline, _prior, _type, _bpp, i, len, acc) when i >= len do
    acc
  end

  defp unfilter_bytes(scanline, prior, type, bpp, i, len, acc) do
    x = :binary.at(scanline, i)
    left = if i >= bpp, do: :binary.at(acc, i - bpp), else: 0
    up = :binary.at(prior, i)
    up_left = if i >= bpp, do: :binary.at(prior, i - bpp), else: 0

    raw =
      case type do
        1 -> band(x + left, 0xFF)
        2 -> band(x + up, 0xFF)
        3 -> band(x + div(left + up, 2), 0xFF)
        4 -> band(x + paeth_predictor(left, up, up_left), 0xFF)
        _ -> x
      end

    unfilter_bytes(scanline, prior, type, bpp, i + 1, len, <<acc::binary, raw::8>>)
  end

  defp paeth_predictor(a, b, c) do
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp build_image(raw_bytes, w, h, 2, _chunks) do
    {:ok,
     %Image{
       format: :png,
       width: w,
       height: h,
       color_space: :rgb,
       data: :zlib.compress(raw_bytes),
       alpha_data: nil
     }}
  end

  defp build_image(raw_bytes, w, h, 6, _chunks) do
    {rgb, alpha} = split_rgba(raw_bytes, [], [])

    {:ok,
     %Image{
       format: :png,
       width: w,
       height: h,
       color_space: :rgb,
       data: :zlib.compress(rgb),
       alpha_data: :zlib.compress(alpha)
     }}
  end

  defp build_image(raw_bytes, w, h, 0, _chunks) do
    {:ok,
     %Image{
       format: :png,
       width: w,
       height: h,
       color_space: :gray,
       data: :zlib.compress(raw_bytes),
       alpha_data: nil
     }}
  end

  defp build_image(raw_bytes, w, h, 4, _chunks) do
    {gray, alpha} = split_ga(raw_bytes, [], [])

    {:ok,
     %Image{
       format: :png,
       width: w,
       height: h,
       color_space: :gray,
       data: :zlib.compress(gray),
       alpha_data: :zlib.compress(alpha)
     }}
  end

  defp build_image(raw_bytes, w, h, 3, chunks) do
    palette = chunks.plte || <<>>
    rgb = expand_palette(raw_bytes, palette, [])

    {:ok,
     %Image{
       format: :png,
       width: w,
       height: h,
       color_space: :rgb,
       data: :zlib.compress(rgb),
       alpha_data: nil
     }}
  end

  defp split_rgba(<<>>, rgb_acc, alpha_acc) do
    {IO.iodata_to_binary(Enum.reverse(rgb_acc)), IO.iodata_to_binary(Enum.reverse(alpha_acc))}
  end

  defp split_rgba(<<r::8, g::8, b::8, a::8, rest::binary>>, rgb_acc, alpha_acc) do
    split_rgba(rest, [<<r, g, b>> | rgb_acc], [<<a>> | alpha_acc])
  end

  defp split_ga(<<>>, gray_acc, alpha_acc) do
    {IO.iodata_to_binary(Enum.reverse(gray_acc)), IO.iodata_to_binary(Enum.reverse(alpha_acc))}
  end

  defp split_ga(<<g::8, a::8, rest::binary>>, gray_acc, alpha_acc) do
    split_ga(rest, [<<g>> | gray_acc], [<<a>> | alpha_acc])
  end

  defp expand_palette(<<>>, _palette, acc) do
    IO.iodata_to_binary(Enum.reverse(acc))
  end

  defp expand_palette(<<idx::8, rest::binary>>, palette, acc) do
    offset = idx * 3

    color =
      if byte_size(palette) >= offset + 3 do
        binary_part(palette, offset, 3)
      else
        <<0, 0, 0>>
      end

    expand_palette(rest, palette, [color | acc])
  end
end
