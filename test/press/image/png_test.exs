defmodule Press.Image.PNGTest do
  use ExUnit.Case, async: true

  alias Press.Image.PNG

  defp make_png(width, height, color_type, scanlines, extra_chunks \\ []) do
    ihdr_data = <<width::32, height::32, 8, color_type, 0, 0, 0>>
    ihdr_chunk = chunk("IHDR", ihdr_data)

    idat_payload = :zlib.compress(scanlines)
    idat_chunk = chunk("IDAT", idat_payload)
    iend_chunk = chunk("IEND", "")

    chunks = [ihdr_chunk] ++ extra_chunks ++ [idat_chunk, iend_chunk]
    <<137, 80, 78, 71, 13, 10, 26, 10>> <> IO.iodata_to_binary(chunks)
  end

  defp chunk(type, data) do
    len = byte_size(data)
    crc = :erlang.crc32(type <> data)
    <<len::32, type::binary-size(4), data::binary, crc::32>>
  end

  describe "parse/1" do
    test "parses a standard RGB PNG (color type 2)" do
      # 2x1 RGB image: filter byte (0) + 2 pixels * 3 bytes (R,G,B) = 7 bytes
      scanlines = <<0, 255, 0, 0, 0, 255, 0>>
      png_bytes = make_png(2, 1, 2, scanlines)

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.format == :png
      assert image.width == 2
      assert image.height == 1
      assert image.color_space == :rgb
      assert image.alpha_data == nil
      assert is_binary(image.data)
      assert :zlib.uncompress(image.data) == <<255, 0, 0, 0, 255, 0>>
    end

    test "parses an RGBA PNG (color type 6) and separates color and alpha channels" do
      # 2x1 RGBA image: filter byte (0) + 2 pixels * 4 bytes (R,G,B,A)
      scanlines = <<0, 255, 0, 0, 128, 0, 0, 255, 200>>
      png_bytes = make_png(2, 1, 6, scanlines)

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.format == :png
      assert image.width == 2
      assert image.height == 1
      assert image.color_space == :rgb
      assert is_binary(image.data)
      assert is_binary(image.alpha_data)

      # RGB channels
      assert :zlib.uncompress(image.data) == <<255, 0, 0, 0, 0, 255>>
      # Alpha channel (grayscale mask)
      assert :zlib.uncompress(image.alpha_data) == <<128, 200>>
    end

    test "handles Sub and Up filter methods across scanlines" do
      # 2x2 RGB image:
      # Line 0: filter 0 (None), pixel1: (10, 20, 30), pixel2: (40, 50, 60)
      # Line 1: filter 2 (Up), diffs: (+5, +5, +5), (+10, +10, +10) -> (15, 25, 35), (50, 60, 70)
      line0 = <<0, 10, 20, 30, 40, 50, 60>>
      line1 = <<2, 5, 5, 5, 10, 10, 10>>
      png_bytes = make_png(2, 2, 2, line0 <> line1)

      assert {:ok, image} = PNG.parse(png_bytes)
      uncompressed = :zlib.uncompress(image.data)

      expected = <<10, 20, 30, 40, 50, 60, 15, 25, 35, 50, 60, 70>>
      assert uncompressed == expected
    end

    test "parses a Grayscale PNG (color type 0)" do
      scanlines = <<0, 100, 200>>
      png_bytes = make_png(2, 1, 0, scanlines)

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.format == :png
      assert image.width == 2
      assert image.height == 1
      assert image.color_space == :gray
      assert image.alpha_data == nil
      assert :zlib.uncompress(image.data) == <<100, 200>>
    end

    test "parses a Grayscale+Alpha PNG (color type 4)" do
      scanlines = <<0, 100, 255, 200, 128>>
      png_bytes = make_png(2, 1, 4, scanlines)

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.format == :png
      assert image.color_space == :gray
      assert :zlib.uncompress(image.data) == <<100, 200>>
      assert :zlib.uncompress(image.alpha_data) == <<255, 128>>
    end

    test "parses an Indexed PNG (color type 3) with PLTE chunk" do
      palette = <<255, 0, 0, 0, 255, 0, 0, 0, 255>>
      plte_chunk = chunk("PLTE", palette)
      scanlines = <<0, 0, 1, 2>>
      png_bytes = make_png(3, 1, 3, scanlines, [plte_chunk])

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.format == :png
      assert image.color_space == :rgb
      assert :zlib.uncompress(image.data) == <<255, 0, 0, 0, 255, 0, 0, 0, 255>>
    end

    test "handles Average (3) and Paeth (4) filter methods" do
      line0 = <<0, 10, 20, 30, 40, 50, 60>>
      line1 = <<3, 5, 5, 5, 5, 5, 5>>
      line2 = <<4, 2, 2, 2, 2, 2, 2>>
      png_bytes = make_png(2, 3, 2, line0 <> line1 <> line2)

      assert {:ok, image} = PNG.parse(png_bytes)
      assert image.height == 3
      assert is_binary(image.data)
    end

    test "returns error on corrupt IDAT or invalid PNG data" do
      assert {:error, :invalid_png} = PNG.parse("not a png")
      assert {:error, :invalid_png} = PNG.parse(<<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>)

      # Corrupted IDAT payload
      bad_idat = chunk("IDAT", "not zlib compressed")
      ihdr = chunk("IHDR", <<2::32, 1::32, 8, 2, 0, 0, 0>>)
      iend = chunk("IEND", "")
      bad_png = <<137, 80, 78, 71, 13, 10, 26, 10>> <> ihdr <> bad_idat <> iend
      assert {:error, :invalid_png} = PNG.parse(bad_png)
    end
  end
end
