defmodule Press.Layout.FragmentTest do
  use ExUnit.Case, async: true

  alias Press.Layout.{Box, Fragment}

  defp zero, do: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}

  defp child(y, height, opts \\ []) do
    %Box{
      type: :block,
      tag: Keyword.get(opts, :tag, "p"),
      x: 0.0,
      y: y,
      width: 100.0,
      height: height,
      margin: zero(),
      padding: zero(),
      border_width: zero(),
      header_row: Keyword.get(opts, :header_row, false)
    }
  end

  defp container(children, opts \\ []) do
    %Box{
      type: Keyword.get(opts, :type, :block),
      tag: Keyword.get(opts, :tag, "div"),
      x: 0.0,
      y: 0.0,
      width: 100.0,
      height: Enum.reduce(children, 0.0, &(&1.height + &2)),
      margin: zero(),
      padding: Keyword.get(opts, :padding, zero()),
      border_width: Keyword.get(opts, :border_width, zero()),
      children: children
    }
  end

  describe "split/2" do
    test "keeps the children above the limit and moves the rest into the tail" do
      box = container([child(0.0, 40.0), child(40.0, 40.0), child(80.0, 40.0)])

      assert {:split, head, tail} = Fragment.split(box, 80.0)
      assert length(head.children) == 2
      assert length(tail.children) == 1
    end

    test "the tail keeps its children where the layout put them" do
      box = container([child(0.0, 40.0), child(40.0, 40.0), child(80.0, 40.0)])

      assert {:split, _head, tail} = Fragment.split(box, 80.0)
      assert [only] = tail.children
      assert only.y == 80.0
      assert tail.y == 80.0
    end

    test "the head drops its bottom edge and the tail its top, so the box reads as one" do
      box =
        container(
          [child(0.0, 40.0), child(40.0, 40.0)],
          padding: %{top: 5.0, right: 5.0, bottom: 5.0, left: 5.0},
          border_width: %{top: 2.0, right: 2.0, bottom: 2.0, left: 2.0}
        )

      assert {:split, head, tail} = Fragment.split(box, 40.0)
      assert head.padding.top == 5.0
      assert head.padding.bottom == 0.0
      assert head.border_width.bottom == 0.0
      assert tail.padding.top == 0.0
      assert tail.border_width.top == 0.0
      assert tail.padding.bottom == 5.0
    end

    test "a table repeats its header rows at the top of the tail" do
      box =
        container(
          [
            child(0.0, 10.0, tag: "tr", header_row: true),
            child(10.0, 40.0, tag: "tr"),
            child(50.0, 40.0, tag: "tr"),
            child(90.0, 40.0, tag: "tr")
          ],
          type: :table,
          tag: "table"
        )

      assert {:split, head, tail} = Fragment.split(box, 90.0)
      assert Enum.count(head.children, & &1.header_row) == 1
      assert Enum.count(tail.children, & &1.header_row) == 1
      # The repeated header does not consume one of the body rows.
      assert Enum.count(head.children, &(not &1.header_row)) == 2
      assert Enum.count(tail.children, &(not &1.header_row)) == 1
    end

    test "the repeated header sits above the rows it belongs to" do
      box =
        container(
          [
            child(0.0, 10.0, tag: "tr", header_row: true),
            child(10.0, 40.0, tag: "tr"),
            child(50.0, 40.0, tag: "tr")
          ],
          type: :table,
          tag: "table"
        )

      assert {:split, _head, tail} = Fragment.split(box, 50.0)
      [header | rows] = tail.children
      assert header.header_row
      assert Enum.all?(rows, &(&1.y >= header.y + header.height))
    end

    test "is indivisible when not even the first child fits" do
      box = container([child(0.0, 100.0), child(100.0, 40.0)])
      assert Fragment.split(box, 50.0) == :indivisible
    end

    test "is indivisible when everything already fits" do
      box = container([child(0.0, 40.0), child(40.0, 40.0)])
      assert Fragment.split(box, 500.0) == :indivisible
    end

    test "a childless box has no break opportunity" do
      assert Fragment.split(container([]), 10.0) == :indivisible
    end

    test "a line of text is never broken apart" do
      line = %Box{child(0.0, 40.0) | type: :line, children: [child(0.0, 40.0)]}
      assert Fragment.split(line, 10.0) == :indivisible
    end
  end
end
