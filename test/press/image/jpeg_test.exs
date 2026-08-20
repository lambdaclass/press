defmodule Press.Image.JPEGTest do
  use ExUnit.Case, async: true

  alias Press.Image.JPEG

  # Minimal 10x20 RGB JPEG structure with SOI, SOF0, and EOI markers
  @sample_jpeg <<
    0xFF, 0xD8, # SOI
    0xFF, 0xE0, 0x00, 0x10, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, # APP0
    0xFF, 0xC0, 0x00, 0x11, 8, 0x00, 0x14, 0x00, 0x0A, 3, 1, 0x11, 0, 2, 0x11, 0, 3, 0x11, 0, # SOF0: 8-bit, 20px high, 10px wide, 3 components
    0xFF, 0xD9 # EOI
  >>

  describe "parse/1" do
    test "extracts width, height, and color space from a valid JPEG binary" do
      assert {:ok, image} = JPEG.parse(@sample_jpeg)
      assert image.format == :jpeg
      assert image.width == 10
      assert image.height == 20
      assert image.color_space == :rgb
      assert image.data == @sample_jpeg
    end

    test "returns error on non-JPEG data" do
      assert {:error, :invalid_jpeg} = JPEG.parse("not a jpeg")
    end
  end
end
