defmodule PressTest do
  use ExUnit.Case, async: true

  test "renders simple HTML to a valid PDF binary" do
    html = "<h1>Hello world!</h1>"
    assert {:ok, pdf_bytes} = Press.render(html)
    assert is_binary(pdf_bytes)
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    assert String.ends_with?(pdf_bytes, "%%EOF")
  end

  test "renders HTML with external CSS option" do
    html = "<h1>Hello</h1><p>World</p>"
    css = "h1 { color: red; font-size: 24pt; } p { font-size: 14pt; }"

    assert {:ok, pdf_bytes} = Press.render(html, css: css)
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
  end

  test "renders HTML with embedded style and @page configuration" do
    html = """
    <style>
      @page { size: letter; margin: 1in; }
      body { font-family: times; font-size: 12pt; }
      h1 { color: blue; }
    </style>
    <h1>Invoice #999</h1>
    <p>Thank you for your business.</p>
    """

    assert {:ok, pdf_bytes} = Press.render(html)
    assert String.starts_with?(pdf_bytes, "%PDF-1.4")
    assert pdf_bytes =~ "/MediaBox [0 0 612 792]"
  end
end
