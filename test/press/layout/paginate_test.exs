defmodule Press.Layout.PaginateTest do
  use ExUnit.Case, async: true

  alias Press.Layout.{Box, Paginate}

  defp page_config(h \\ 800.0, top \\ 50.0, bottom \\ 50.0) do
    %{
      size: {600.0, h},
      margin: %{top: top, right: 50.0, bottom: bottom, left: 50.0}
    }
  end

  defp block_box(tag, height, y, page_break_opts \\ %{}) do
    %Box{
      type: :block,
      tag: tag,
      x: 50.0,
      y: y,
      width: 500.0,
      height: height,
      margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
      computed: page_break_opts
    }
  end

  describe "paginate/2" do
    test "fits boxes into a single page when total height is within flow area" do
      # Usable height = 800 - 50*2 = 700.0
      b1 = block_box("p", 200.0, 50.0)
      b2 = block_box("p", 300.0, 250.0)
      root = %Box{type: :root, children: [b1, b2]}

      pages = Paginate.paginate(root, page_config())

      assert length(pages) == 1
      [page1] = pages
      assert page1.number == 1
      assert length(page1.boxes) == 2
    end

    test "breaks into multiple pages when content overflows page flow height" do
      # Usable height = 700.0. 3 boxes of 300.0 each = 900.0 -> 2 pages
      b1 = block_box("p", 300.0, 50.0)
      b2 = block_box("p", 300.0, 350.0)
      b3 = block_box("p", 300.0, 650.0)
      root = %Box{type: :root, children: [b1, b2, b3]}

      pages = Paginate.paginate(root, page_config())

      assert length(pages) == 2
      [page1, page2] = pages
      assert page1.number == 1
      assert page2.number == 2

      # Page 1 has b1 and b2 (600pt <= 700pt)
      assert length(page1.boxes) == 2
      # Page 2 has b3 (300pt)
      assert length(page2.boxes) == 1
    end

    test "repeats header and footer on every generated page" do
      header = %Box{
        type: :block,
        tag: "header",
        x: 50.0,
        y: 50.0,
        width: 500.0,
        height: 40.0,
        margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        computed: %{}
      }

      footer = %Box{
        type: :block,
        tag: "footer",
        x: 50.0,
        y: 710.0,
        width: 500.0,
        height: 40.0,
        margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        padding: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        border_width: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        computed: %{}
      }

      # Flow height = 800 - 50*2 - 40(header) - 40(footer) = 620.0
      b1 = block_box("p", 400.0, 90.0)
      b2 = block_box("p", 400.0, 490.0)

      root = %Box{type: :root, children: [header, b1, b2, footer]}
      pages = Paginate.paginate(root, page_config())

      assert length(pages) == 2

      for page <- pages do
        tags = Enum.map(page.boxes, & &1.tag)
        assert "header" in tags
        assert "footer" in tags
      end
    end

    test "forces a new page on page-break-before: always" do
      b1 = block_box("p", 100.0, 50.0)
      b2 = block_box("p", 100.0, 150.0, %{page_break_before: :always})
      root = %Box{type: :root, children: [b1, b2]}

      pages = Paginate.paginate(root, page_config())

      assert length(pages) == 2
      [page1, page2] = pages
      assert length(page1.boxes) == 1
      assert length(page2.boxes) == 1
    end
  end
end
