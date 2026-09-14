defmodule Press.Layout.BreakingTest do
  use ExUnit.Case, async: true

  alias Press.Layout.{Box, Page}

  defp pages(html, opts) do
    dom = Press.HTML.Parser.parse(html)
    {page_css, rules} = Press.CSS.Parser.parse(embedded_css(dom))

    config =
      Press.Style.Cascade.page_config([], page_css)
      |> Map.merge(Map.new(opts))

    Press.Style.Cascade.build(dom, [], rules)
    |> Press.Layout.build(config, %{})
    |> Press.Layout.Paginate.paginate(config)
  end

  defp embedded_css(nodes) do
    nodes
    |> Enum.flat_map(fn
      %Press.HTML.Element{tag: "style", children: ch} ->
        Enum.map(ch, fn %Press.HTML.Text{content: c} -> c end)

      %Press.HTML.Element{children: ch} ->
        [embedded_css(ch)]

      _ ->
        []
    end)
    |> Enum.join("\n")
  end

  defp texts(%Box{} = box) do
    own = if box.text, do: [box.text], else: []
    own ++ Enum.flat_map(box.children || [], &texts/1)
  end

  defp texts(%Page{boxes: boxes}), do: Enum.flat_map(boxes, &texts/1)

  defp rows(n, tag) do
    Enum.map_join(1..n, "", fn i -> "<div class=\"row\">#{tag}-#{i}</div>" end)
  end

  describe "page-break-inside: avoid" do
    @css """
    * { margin: 0; padding: 0 }
    body { font-size: 10px; line-height: 20px }
    .row { height: 20px }
    """

    test "a block that does not fit moves whole to the next page" do
      html = """
      <html><head><style>#{@css}
      .group { page-break-inside: avoid }
      </style></head><body>
      <div class="filler">#{rows(20, "f")}</div>
      <div class="group">#{rows(15, "g")}</div>
      </body></html>
      """

      [p1, p2] = pages(html, size: {400.0, 500.0}, margin: %{top: 20.0, right: 20.0, bottom: 20.0, left: 20.0})

      refute Enum.any?(texts(p1), &String.starts_with?(&1, "g-"))
      assert "g-1" in texts(p2)
      assert "g-15" in texts(p2)
    end

    test "without it the same block is split across the page edge" do
      html = """
      <html><head><style>#{@css}</style></head><body>
      <div class="filler">#{rows(20, "f")}</div>
      <div class="group">#{rows(15, "g")}</div>
      </body></html>
      """

      [p1, _p2] = pages(html, size: {400.0, 500.0}, margin: %{top: 20.0, right: 20.0, bottom: 20.0, left: 20.0})

      assert Enum.any?(texts(p1), &String.starts_with?(&1, "g-"))
    end

    test "a block taller than any page is broken anyway rather than running off it" do
      html = """
      <html><head><style>#{@css}
      .group { page-break-inside: avoid }
      </style></head><body>
      <div class="group">#{rows(60, "g")}</div>
      </body></html>
      """

      pages = pages(html, size: {400.0, 500.0}, margin: %{top: 20.0, right: 20.0, bottom: 20.0, left: 20.0})

      assert length(pages) > 1
      assert pages |> Enum.flat_map(&texts/1) |> length() == 60

      for page <- pages do
        bottom = page |> boxes_bottom()
        assert bottom <= page.height - 20.0 + 0.01
      end
    end

    defp boxes_bottom(%Page{boxes: boxes}) do
      boxes
      |> Enum.map(&(&1.y + Box.outer_height(&1)))
      |> Enum.max(fn -> 0.0 end)
    end
  end

  describe "overflow-wrap: break-word" do
    @long "supercalifragilisticoespialidosoyademasunpocomaslargoparaquenoentre"

    defp line_count(html) do
      [page] = pages(html, size: {200.0, 500.0}, margin: %{top: 10.0, right: 10.0, bottom: 10.0, left: 10.0})
      page |> texts() |> length()
    end

    test "a word wider than its column is split instead of overflowing" do
      html = """
      <html><head><style>
      * { margin: 0; padding: 0 }
      body { font-size: 12px; overflow-wrap: break-word }
      </style></head><body><div>#{@long}</div></body></html>
      """

      [page] = pages(html, size: {200.0, 500.0}, margin: %{top: 10.0, right: 10.0, bottom: 10.0, left: 10.0})
      pieces = texts(page)

      assert length(pieces) > 1
      assert Enum.join(pieces) == @long
    end

    test "word-wrap is accepted as a spelling of the same thing" do
      html = """
      <html><head><style>
      * { margin: 0; padding: 0 }
      body { font-size: 12px; word-wrap: break-word }
      </style></head><body><div>#{@long}</div></body></html>
      """

      assert line_count(html) > 1
    end

    test "without it the word stays on one line and overflows" do
      html = """
      <html><head><style>
      * { margin: 0; padding: 0 }
      body { font-size: 12px }
      </style></head><body><div>#{@long}</div></body></html>
      """

      assert line_count(html) == 1
    end

    test "a word that fits is never split" do
      html = """
      <html><head><style>
      * { margin: 0; padding: 0 }
      body { font-size: 12px; overflow-wrap: break-word }
      </style></head><body><div>corto</div></body></html>
      """

      [page] = pages(html, size: {200.0, 500.0}, margin: %{top: 10.0, right: 10.0, bottom: 10.0, left: 10.0})
      assert texts(page) == ["corto"]
    end
  end
end
