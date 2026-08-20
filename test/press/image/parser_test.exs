defmodule Press.Image.ParserTest do
  use ExUnit.Case, async: true

  alias Press.Image.Parser

  @sample_jpeg <<
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    "JFIF",
    0,
    1,
    1,
    0,
    0,
    1,
    0,
    1,
    0,
    0,
    0xFF,
    0xC0,
    0x00,
    0x11,
    8,
    0x00,
    0x14,
    0x00,
    0x0A,
    3,
    1,
    0x11,
    0,
    2,
    0x11,
    0,
    3,
    0x11,
    0,
    0xFF,
    0xD9
  >>

  describe "load/2" do
    test "loads image from opts[:images] map" do
      images = %{"logo.jpg" => @sample_jpeg}

      assert {:ok, img} = Parser.load("logo.jpg", images)
      assert img.format == :jpeg
      assert img.width == 10
      assert img.height == 20
    end

    test "loads image from base64 data URI" do
      b64 = Base.encode64(@sample_jpeg)
      uri = "data:image/jpeg;base64,#{b64}"

      assert {:ok, img} = Parser.load(uri, %{})
      assert img.format == :jpeg
      assert img.width == 10
      assert img.height == 20
    end

    test "returns error when image is not in map" do
      assert {:error, {:image_not_found, "missing.png"}} = Parser.load("missing.png", %{})
    end

    test "returns error on invalid data URI format" do
      assert {:error, :invalid_data_uri} = Parser.load("data:text/plain;base64,abc", %{})
    end

    test "returns error on invalid base64 in data URI" do
      assert {:error, :invalid_base64} = Parser.load("data:image/png;base64,!!!invalid!!!", %{})
    end

    test "returns error on unsupported binary format" do
      assert {:error, :unsupported_format} = Parser.load("file.gif", %{"file.gif" => "GIF89a..."})
    end
  end
end
