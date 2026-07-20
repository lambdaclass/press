defmodule Press.PDF.ContentStreamTest do
  use ExUnit.Case, async: true

  alias Press.PDF.ContentStream

  test "renders a text op" do
    ops = [{:text, 10.0, 20.0, :helvetica_bold, 24, {0, 0, 0}, "Hello world!"}]
    result = ContentStream.render(ops, %{helvetica_bold: "/F1"})

    assert result =~ "0 0 0 rg"
    assert result =~ "BT"
    assert result =~ "/F1 24 Tf"
    assert result =~ "10 20 Td"
    assert result =~ "(Hello world!) Tj"
    assert result =~ "ET"
  end

  test "escapes parentheses in text ops" do
    ops = [{:text, 0.0, 0.0, :helvetica, 12, {0, 0, 0}, "a (b) c"}]
    result = ContentStream.render(ops, %{helvetica: "/F1"})

    assert result =~ "(a \\(b\\) c) Tj"
  end

  test "renders a filled and stroked rect op" do
    ops = [{:rect, 1.0, 2.0, 3.0, 4.0, {0.9, 0.9, 0.9}, {0, 0, 0}, 1.5}]
    result = ContentStream.render(ops, %{})

    assert result =~ "0.9 0.9 0.9 rg"
    assert result =~ "0 0 0 RG"
    assert result =~ "1.5 w"
    assert result =~ "1 2 3 4 re"
    assert result =~ "\nB\n"
  end

  test "renders a fill-only rect with the f operator" do
    ops = [{:rect, 0.0, 0.0, 1.0, 1.0, {1, 0, 0}, nil, 1.0}]
    result = ContentStream.render(ops, %{})

    assert result =~ "\nf\n"
    refute result =~ "RG"
  end

  test "renders a stroke-only rect with the S operator" do
    ops = [{:rect, 0.0, 0.0, 1.0, 1.0, nil, {0, 0, 0}, 1.0}]
    result = ContentStream.render(ops, %{})

    assert result =~ "\nS\n"
    refute result =~ "rg"
  end
end
