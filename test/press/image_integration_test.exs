defmodule Press.ImageIntegrationTest do
  use ExUnit.Case, async: true

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

  test "renders HTML document with JPEG image from opts[:images]" do
    html = """
    <h1>Company Header</h1>
    <img src="img/logo.jpg" width="100" height="50">
    <p>Document Content</p>
    """

    assert {:ok, pdf_bytes} = Press.render(html, images: %{"img/logo.jpg" => @sample_jpeg})

    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    assert pdf_bytes =~ "/XObject << /Im1"
    assert pdf_bytes =~ "/Filter /DCTDecode"
    assert pdf_bytes =~ "/Im1 Do"
  end

  test "renders HTML document with PNG image from Base64 Data URI" do
    ihdr_data = <<2::32, 1::32, 8, 6, 0, 0, 0>>
    ihdr_crc = :erlang.crc32("IHDR" <> ihdr_data)
    ihdr_chunk = <<13::32, "IHDR", ihdr_data::binary, ihdr_crc::32>>

    idat_payload = :zlib.compress(<<0, 255, 0, 0, 128, 0, 0, 255, 200>>)
    idat_crc = :erlang.crc32("IDAT" <> idat_payload)
    idat_chunk = <<byte_size(idat_payload)::32, "IDAT", idat_payload::binary, idat_crc::32>>

    iend_crc = :erlang.crc32("IEND")
    iend_chunk = <<0::32, "IEND", iend_crc::32>>

    png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>> <> ihdr_chunk <> idat_chunk <> iend_chunk
    b64 = Base.encode64(png_bytes)
    data_uri = "data:image/png;base64,#{b64}"

    html = """
    <h1>Logo with Alpha</h1>
    <img src="#{data_uri}">
    """

    assert {:ok, pdf_bytes} = Press.render(html)

    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    assert pdf_bytes =~ "/Filter /FlateDecode"
    assert pdf_bytes =~ "/SMask"
    assert pdf_bytes =~ "/Im1 Do"
  end

  test "renders image with only width or only height preserving aspect ratio" do
    html = """
    <img src="img/logo.jpg" width="100pt">
    <img src="img/logo.jpg" height="40px">
    <img src="img/missing.jpg">
    """

    assert {:ok, pdf_bytes} = Press.render(html, images: %{"img/logo.jpg" => @sample_jpeg})
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
  end

  test "renders image with percentage width from CSS" do
    html = """
    <style>
      img.custom { width: 50%; margin: 10px; padding: 5px; }
    </style>
    <img class="custom" src="img/logo.jpg">
    """

    assert {:ok, pdf_bytes} = Press.render(html, images: %{"img/logo.jpg" => @sample_jpeg})
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
  end
end
