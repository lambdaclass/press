# PDF Writer Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the low-level PDF object writer (`Press.PDF.*`) that can turn an in-memory description of pages (text placed with one of the 14 standard PDF fonts, filled/stroked rectangles) into a valid, openable PDF binary — with no HTML/CSS involved yet.

**Architecture:** A small builder API (`Press.PDF.Document`/`Press.PDF.Page`) accumulates drawing operations per page as plain data. `Press.PDF.ContentStream` renders those operations into PDF content-stream operator bytes. `Press.PDF.Writer` assembles the full object graph (Catalog, Pages, each Page, each page's content stream, one Font object per distinct font used), tracks byte offsets while serializing, and writes the header, objects, xref table, and trailer. `Press.PDF.Syntax` and `Press.PDF.Fonts` hold small shared primitives (number/string formatting, base-14 font name table).

**Tech Stack:** Elixir, ExUnit. No runtime dependencies (per `docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`).

This is Phase 1 of the `press` HTML+CSS-to-PDF project. It deliberately does not touch HTML or CSS — it's the rendering target every later phase (layout, pagination, images) will build on top of. Read the design spec (`docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`) for full project context; this plan only implements the "PDF object model" / "PDF writer" pieces of that architecture.

---

## Task 1: PDF value syntax helpers

**Files:**
- Create: `lib/press/pdf/syntax.ex`
- Test: `test/press/pdf/syntax_test.exs`

PDF numbers and literal strings have specific formatting/escaping rules. This task builds the two shared helpers every later task uses.

- [x] **Step 1: Write the failing tests**

```elixir
defmodule Press.PDF.SyntaxTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Syntax

  describe "number/1" do
    test "renders integers without a decimal point" do
      assert Syntax.number(12) == "12"
      assert Syntax.number(0) == "0"
    end

    test "renders whole-number floats without a decimal point" do
      assert Syntax.number(12.0) == "12"
    end

    test "renders fractional floats trimmed of trailing zeros" do
      assert Syntax.number(12.5) == "12.5"
      assert Syntax.number(0.25) == "0.25"
    end
  end

  describe "escape_string/1" do
    test "escapes backslashes and parentheses" do
      assert Syntax.escape_string("a(b)c\\d") == "a\\(b\\)c\\\\d"
    end

    test "leaves plain text untouched" do
      assert Syntax.escape_string("Hello world!") == "Hello world!"
    end
  end
end
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/pdf/syntax_test.exs`
Expected: FAIL — `Press.PDF.Syntax` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.PDF.Syntax do
  @moduledoc false

  def number(n) when is_integer(n), do: Integer.to_string(n)

  def number(n) when is_float(n) do
    if n == Float.round(n) do
      n |> trunc() |> Integer.to_string()
    else
      n
      |> :erlang.float_to_binary(decimals: 4)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end

  def escape_string(text) when is_binary(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/pdf/syntax_test.exs`
Expected: PASS (5 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/pdf/syntax.ex test/press/pdf/syntax_test.exs
git commit -m "Add PDF number/string syntax helpers"
```

---

## Task 2: Base-14 font name table

**Files:**
- Create: `lib/press/pdf/fonts.ex`
- Test: `test/press/pdf/fonts_test.exs`

The 14 standard PDF fonts don't need to be embedded, but the writer needs to map our internal font atoms (`:helvetica_bold`) to the exact `BaseFont` names PDF readers expect (`"Helvetica-Bold"`).

- [x] **Step 1: Write the failing tests**

```elixir
defmodule Press.PDF.FontsTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Fonts

  test "maps every standard font atom to its PDF BaseFont name" do
    assert Fonts.base_font_name(:helvetica) == "Helvetica"
    assert Fonts.base_font_name(:helvetica_bold) == "Helvetica-Bold"
    assert Fonts.base_font_name(:helvetica_oblique) == "Helvetica-Oblique"
    assert Fonts.base_font_name(:helvetica_bold_oblique) == "Helvetica-BoldOblique"
    assert Fonts.base_font_name(:times_roman) == "Times-Roman"
    assert Fonts.base_font_name(:times_bold) == "Times-Bold"
    assert Fonts.base_font_name(:times_italic) == "Times-Italic"
    assert Fonts.base_font_name(:times_bold_italic) == "Times-BoldItalic"
    assert Fonts.base_font_name(:courier) == "Courier"
    assert Fonts.base_font_name(:courier_bold) == "Courier-Bold"
    assert Fonts.base_font_name(:courier_oblique) == "Courier-Oblique"
    assert Fonts.base_font_name(:courier_bold_oblique) == "Courier-BoldOblique"
    assert Fonts.base_font_name(:symbol) == "Symbol"
    assert Fonts.base_font_name(:zapf_dingbats) == "ZapfDingbats"
  end

  test "standard_fonts/0 lists all 14 atoms" do
    assert length(Fonts.standard_fonts()) == 14
    assert :helvetica in Fonts.standard_fonts()
  end
end
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/pdf/fonts_test.exs`
Expected: FAIL — `Press.PDF.Fonts` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.PDF.Fonts do
  @moduledoc false

  @base_fonts %{
    helvetica: "Helvetica",
    helvetica_bold: "Helvetica-Bold",
    helvetica_oblique: "Helvetica-Oblique",
    helvetica_bold_oblique: "Helvetica-BoldOblique",
    times_roman: "Times-Roman",
    times_bold: "Times-Bold",
    times_italic: "Times-Italic",
    times_bold_italic: "Times-BoldItalic",
    courier: "Courier",
    courier_bold: "Courier-Bold",
    courier_oblique: "Courier-Oblique",
    courier_bold_oblique: "Courier-BoldOblique",
    symbol: "Symbol",
    zapf_dingbats: "ZapfDingbats"
  }

  def base_font_name(atom), do: Map.fetch!(@base_fonts, atom)

  def standard_fonts, do: Map.keys(@base_fonts)
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/pdf/fonts_test.exs`
Expected: PASS (2 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/pdf/fonts.ex test/press/pdf/fonts_test.exs
git commit -m "Add base-14 PDF font name table"
```

---

## Task 3: Document/Page builder

**Files:**
- Create: `lib/press/pdf/document.ex`
- Create: `lib/press/pdf/page.ex`
- Test: `test/press/pdf/document_test.exs`

This is the in-memory API later phases (and this plan's own integration test) use to describe pages: add a page, draw text on it, draw a rectangle on it. It only builds data — no PDF bytes yet.

- [x] **Step 1: Write the failing tests**

```elixir
defmodule Press.PDF.DocumentTest do
  use ExUnit.Case, async: true

  alias Press.PDF.Document

  test "new/0 starts with no pages" do
    assert Document.new().pages == []
  end

  test "add_page/3 appends a page and returns its index" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)

    assert index == 0
    assert [%Press.PDF.Page{width: 595.0, height: 842.0, ops: []}] = doc.pages
  end

  test "add_page/3 returns increasing indexes for successive pages" do
    {doc, index0} = Document.new() |> Document.add_page(595.0, 842.0)
    {doc, index1} = Document.add_page(doc, 595.0, 842.0)

    assert index0 == 0
    assert index1 == 1
    assert length(doc.pages) == 2
  end

  test "draw_text/6 appends a text op to the given page" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)
    doc = Document.draw_text(doc, index, 10.0, 20.0, "Hello world!", font: :helvetica_bold, size: 24)

    assert [%Press.PDF.Page{ops: [{:text, 10.0, 20.0, :helvetica_bold, 24, {0, 0, 0}, "Hello world!"}]}] =
             doc.pages
  end

  test "draw_text/6 defaults to helvetica, size 12, black" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)
    doc = Document.draw_text(doc, index, 0.0, 0.0, "x")

    assert [%Press.PDF.Page{ops: [{:text, 0.0, 0.0, :helvetica, 12, {0, 0, 0}, "x"}]}] = doc.pages
  end

  test "draw_rect/6 appends a rect op with fill and stroke" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)

    doc =
      Document.draw_rect(doc, index, 1.0, 2.0, 3.0, 4.0,
        fill: {0.9, 0.9, 0.9},
        stroke: {0, 0, 0},
        stroke_width: 1.5
      )

    assert [%Press.PDF.Page{ops: [{:rect, 1.0, 2.0, 3.0, 4.0, {0.9, 0.9, 0.9}, {0, 0, 0}, 1.5}]}] =
             doc.pages
  end

  test "draw_rect/6 defaults to no fill, no stroke, stroke_width 1.0" do
    {doc, index} = Document.new() |> Document.add_page(595.0, 842.0)
    doc = Document.draw_rect(doc, index, 0.0, 0.0, 1.0, 1.0)

    assert [%Press.PDF.Page{ops: [{:rect, 0.0, 0.0, 1.0, 1.0, nil, nil, 1.0}]}] = doc.pages
  end
end
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/pdf/document_test.exs`
Expected: FAIL — `Press.PDF.Document` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
# lib/press/pdf/page.ex
defmodule Press.PDF.Page do
  @moduledoc false

  defstruct width: 595.0, height: 842.0, ops: []
end
```

```elixir
# lib/press/pdf/document.ex
defmodule Press.PDF.Document do
  @moduledoc false

  alias Press.PDF.Page

  defstruct pages: []

  def new, do: %__MODULE__{}

  def add_page(%__MODULE__{pages: pages} = doc, width, height) do
    page = %Page{width: width, height: height, ops: []}
    index = length(pages)
    {%{doc | pages: pages ++ [page]}, index}
  end

  def draw_text(%__MODULE__{} = doc, page_index, x, y, text, opts \\ []) do
    font = Keyword.get(opts, :font, :helvetica)
    size = Keyword.get(opts, :size, 12)
    color = Keyword.get(opts, :color, {0, 0, 0})

    update_page(doc, page_index, fn page ->
      %{page | ops: page.ops ++ [{:text, x, y, font, size, color, text}]}
    end)
  end

  def draw_rect(%__MODULE__{} = doc, page_index, x, y, w, h, opts \\ []) do
    fill = Keyword.get(opts, :fill)
    stroke = Keyword.get(opts, :stroke)
    stroke_width = Keyword.get(opts, :stroke_width, 1.0)

    update_page(doc, page_index, fn page ->
      %{page | ops: page.ops ++ [{:rect, x, y, w, h, fill, stroke, stroke_width}]}
    end)
  end

  defp update_page(%__MODULE__{pages: pages} = doc, index, fun) do
    %{doc | pages: List.update_at(pages, index, fun)}
  end
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/pdf/document_test.exs`
Expected: PASS (7 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/pdf/page.ex lib/press/pdf/document.ex test/press/pdf/document_test.exs
git commit -m "Add PDF document/page builder API"
```

---

## Task 4: Content stream rendering

**Files:**
- Create: `lib/press/pdf/content_stream.ex`
- Test: `test/press/pdf/content_stream_test.exs`

Turns a page's list of `{:text, ...}` / `{:rect, ...}` ops into PDF content-stream operator bytes (the `BT ... ET`, `re`, `f`/`S`/`B` operators a PDF page's content stream is made of).

- [x] **Step 1: Write the failing tests**

```elixir
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
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/pdf/content_stream_test.exs`
Expected: FAIL — `Press.PDF.ContentStream` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.PDF.ContentStream do
  @moduledoc false

  alias Press.PDF.Syntax

  def render(ops, font_resource_names) do
    Enum.map_join(ops, "\n", &render_op(&1, font_resource_names))
  end

  defp render_op({:text, x, y, font, size, {r, g, b}, text}, font_resource_names) do
    resource = Map.fetch!(font_resource_names, font)

    Enum.join(
      [
        "q",
        "#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} rg",
        "BT",
        "#{resource} #{Syntax.number(size)} Tf",
        "#{Syntax.number(x)} #{Syntax.number(y)} Td",
        "(#{Syntax.escape_string(text)}) Tj",
        "ET",
        "Q"
      ],
      "\n"
    )
  end

  defp render_op({:rect, x, y, w, h, fill, stroke, stroke_width}, _font_resource_names) do
    ["q"]
    |> add_fill_color(fill)
    |> add_stroke_color(stroke, stroke_width)
    |> Kernel.++([
      "#{Syntax.number(x)} #{Syntax.number(y)} #{Syntax.number(w)} #{Syntax.number(h)} re",
      paint_operator(fill, stroke),
      "Q"
    ])
    |> Enum.join("\n")
  end

  defp add_fill_color(lines, nil), do: lines

  defp add_fill_color(lines, {r, g, b}) do
    lines ++ ["#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} rg"]
  end

  defp add_stroke_color(lines, nil, _width), do: lines

  defp add_stroke_color(lines, {r, g, b}, width) do
    lines ++
      [
        "#{Syntax.number(r)} #{Syntax.number(g)} #{Syntax.number(b)} RG",
        "#{Syntax.number(width)} w"
      ]
  end

  defp paint_operator(nil, nil), do: "n"
  defp paint_operator(_fill, nil), do: "f"
  defp paint_operator(nil, _stroke), do: "S"
  defp paint_operator(_fill, _stroke), do: "B"
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/pdf/content_stream_test.exs`
Expected: PASS (5 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/pdf/content_stream.ex test/press/pdf/content_stream_test.exs
git commit -m "Add PDF content stream rendering for text and rect ops"
```

---

## Task 5: Object assembly, xref/trailer, and `to_binary/1`

**Files:**
- Create: `lib/press/pdf/writer.ex`
- Test: `test/press/pdf/writer_test.exs`

Assigns PDF indirect object numbers (`1` = Catalog, `2` = Pages, then two objects per page — Page and its Contents stream — then one Font object per distinct font used across the document), serializes every object while tracking byte offsets, and writes the header/xref/trailer.

- [x] **Step 1: Write the failing tests**

```elixir
defmodule Press.PDF.WriterTest do
  use ExUnit.Case, async: true

  alias Press.PDF.{Document, Writer}

  test "starts with the PDF header" do
    binary = Document.new() |> then(fn doc -> elem(Document.add_page(doc, 595.0, 842.0), 0) end) |> Writer.to_binary()

    assert String.starts_with?(binary, "%PDF-1.4\n")
  end

  test "includes a Pages object with the right /Count for multiple pages" do
    doc = Document.new()
    {doc, _} = Document.add_page(doc, 595.0, 842.0)
    {doc, _} = Document.add_page(doc, 595.0, 842.0)

    binary = Writer.to_binary(doc)

    assert binary =~ "/Type /Pages /Kids [3 0 R 5 0 R] /Count 2"
  end

  test "includes exactly one Font object per distinct font used, shared across pages" do
    doc = Document.new()
    {doc, p0} = Document.add_page(doc, 595.0, 842.0)
    {doc, p1} = Document.add_page(doc, 595.0, 842.0)
    doc = Document.draw_text(doc, p0, 0.0, 0.0, "a", font: :helvetica)
    doc = Document.draw_text(doc, p1, 0.0, 0.0, "b", font: :helvetica)

    binary = Writer.to_binary(doc)

    assert length(Regex.scan(~r{/BaseFont /Helvetica\b}, binary)) == 1
  end

  test "every xref offset points at the matching \"N 0 obj\"" do
    doc = Document.new()
    {doc, p} = Document.add_page(doc, 595.0, 842.0)
    doc = Document.draw_text(doc, p, 10.0, 20.0, "Hello world!", font: :helvetica_bold, size: 24)

    binary = Writer.to_binary(doc)

    [_before, xref_and_trailer] = String.split(binary, "xref\n", parts: 2)
    [entries_block, _trailer] = String.split(xref_and_trailer, "trailer\n", parts: 2)
    ["0 " <> _count | entry_lines] = String.split(entries_block, "\r\n", trim: true)

    entry_lines
    |> Enum.with_index(1)
    |> Enum.each(fn {line, obj_num} ->
      offset = line |> String.slice(0, 10) |> String.to_integer()
      following = binary |> String.slice(offset, byte_size("#{obj_num} 0 obj"))
      assert following == "#{obj_num} 0 obj"
    end)
  end

  test "ends with a valid trailer pointing at object 1 as Root" do
    doc = Document.new()
    {doc, _} = Document.add_page(doc, 595.0, 842.0)

    binary = Writer.to_binary(doc)

    assert binary =~ "trailer\n<< /Size"
    assert binary =~ "/Root 1 0 R"
    assert String.ends_with?(binary, "%%EOF")
  end
end
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `mix test test/press/pdf/writer_test.exs`
Expected: FAIL — `Press.PDF.Writer` is undefined.

- [x] **Step 3: Write the implementation**

```elixir
defmodule Press.PDF.Writer do
  @moduledoc false

  alias Press.PDF.{ContentStream, Document, Fonts, Syntax}

  def to_binary(%Document{pages: pages}) do
    page_count = length(pages)
    fonts = collect_fonts(pages)
    first_font_obj_num = 3 + page_count * 2

    font_resource_names =
      fonts |> Enum.with_index(1) |> Map.new(fn {font, i} -> {font, "/F#{i}"} end)

    font_obj_numbers = fonts |> Enum.with_index(first_font_obj_num) |> Map.new()

    resources = resources_dict(fonts, font_resource_names, font_obj_numbers)
    page_obj_numbers = if page_count == 0, do: [], else: for i <- 0..(page_count - 1), do: 3 + i * 2

    page_and_content_objects =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {page, i} ->
        page_obj_num = 3 + i * 2
        contents_obj_num = 4 + i * 2
        content_bytes = ContentStream.render(page.ops, font_resource_names)

        page_body =
          "<< /Type /Page /Parent 2 0 R " <>
            "/MediaBox [0 0 #{Syntax.number(page.width)} #{Syntax.number(page.height)}] " <>
            "/Resources #{resources} /Contents #{contents_obj_num} 0 R >>"

        [{page_obj_num, page_body}, {contents_obj_num, stream_body(content_bytes)}]
      end)

    catalog = {1, "<< /Type /Catalog /Pages 2 0 R >>"}

    kids = Enum.map_join(page_obj_numbers, " ", &"#{&1} 0 R")
    pages_obj = {2, "<< /Type /Pages /Kids [#{kids}] /Count #{page_count} >>"}

    font_objects =
      for font <- fonts do
        {font_obj_numbers[font],
         "<< /Type /Font /Subtype /Type1 /BaseFont /#{Fonts.base_font_name(font)} >>"}
      end

    objects =
      ([catalog, pages_obj] ++ page_and_content_objects ++ font_objects)
      |> Enum.sort_by(&elem(&1, 0))

    assemble("%PDF-1.4\n", objects)
  end

  defp collect_fonts(pages) do
    pages
    |> Enum.flat_map(fn page ->
      Enum.flat_map(page.ops, fn
        {:text, _x, _y, font, _size, _color, _text} -> [font]
        _other -> []
      end)
    end)
    |> Enum.uniq()
  end

  defp resources_dict(fonts, font_resource_names, font_obj_numbers) do
    entries =
      Enum.map_join(fonts, " ", fn font ->
        "#{font_resource_names[font]} #{font_obj_numbers[font]} 0 R"
      end)

    "<< /Font << #{entries} >> >>"
  end

  defp stream_body(content_bytes) do
    length = IO.iodata_length(content_bytes)
    "<< /Length #{length} >>\nstream\n#{IO.iodata_to_binary(content_bytes)}\nendstream"
  end

  defp assemble(header, objects) do
    {body_iodata, offsets} =
      Enum.reduce(objects, {[], %{}}, fn {num, body}, {acc, offsets} ->
        offset = byte_size(header) + IO.iodata_length(acc)
        obj_iodata = "#{num} 0 obj\n#{body}\nendobj\n"
        {[acc, obj_iodata], Map.put(offsets, num, offset)}
      end)

    xref_offset = byte_size(header) + IO.iodata_length(body_iodata)
    max_obj_num = objects |> Enum.map(&elem(&1, 0)) |> Enum.max()

    xref_entries =
      for num <- 1..max_obj_num do
        pad_offset(Map.fetch!(offsets, num)) <> " 00000 n\r\n"
      end

    xref =
      "xref\n0 #{max_obj_num + 1}\n" <>
        "0000000000 65535 f\r\n" <>
        Enum.join(xref_entries)

    trailer =
      "trailer\n<< /Size #{max_obj_num + 1} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF"

    IO.iodata_to_binary([header, body_iodata, xref, trailer])
  end

  defp pad_offset(offset), do: offset |> Integer.to_string() |> String.pad_leading(10, "0")
end
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `mix test test/press/pdf/writer_test.exs`
Expected: PASS (5 tests, 0 failures)

- [x] **Step 5: Commit**

```bash
git add lib/press/pdf/writer.ex test/press/pdf/writer_test.exs
git commit -m "Add PDF object assembly, xref/trailer, and Writer.to_binary/1"
```

---

## Task 6: End-to-end integration test

**Files:**
- Test: `test/press/pdf/integration_test.exs`

Builds a one-page document with a bordered/filled box and bold "Hello world!" text using only the public `Press.PDF.Document`/`Press.PDF.Writer` API, and checks the produced binary is a structurally valid, openable PDF. This is the acceptance test for Phase 1: if it passes, the PDF writer core is done.

- [x] **Step 1: Write the failing test**

```elixir
defmodule Press.PDF.IntegrationTest do
  use ExUnit.Case, async: true

  alias Press.PDF.{Document, Writer}

  test "produces a structurally valid PDF with a box and text on it" do
    doc = Document.new()
    {doc, page} = Document.add_page(doc, 595.0, 842.0)

    doc =
      doc
      |> Document.draw_rect(page, 50.0, 700.0, 200.0, 80.0,
        fill: {0.9, 0.9, 0.9},
        stroke: {0, 0, 0},
        stroke_width: 1.0
      )
      |> Document.draw_text(page, 60.0, 750.0, "Hello world!", font: :helvetica_bold, size: 24)

    binary = Writer.to_binary(doc)

    assert String.starts_with?(binary, "%PDF-1.4\n")
    assert binary =~ "/BaseFont /Helvetica-Bold"
    assert binary =~ "(Hello world!) Tj"
    assert binary =~ "trailer"
    assert String.ends_with?(binary, "%%EOF")

    tmp_path = Path.join(System.tmp_dir!(), "press_integration_test.pdf")
    File.write!(tmp_path, binary)
    on_exit(fn -> File.rm(tmp_path) end)
  end
end
```

- [x] **Step 2: Run the test to verify it fails or passes**

Run: `mix test test/press/pdf/integration_test.exs`
Expected: Given Tasks 1-5 are already implemented, this should PASS immediately — it exercises only the already-built public API. If it fails, that means Tasks 1-5 have a bug; fix the relevant module (not this test) before continuing.

- [x] **Step 3: Manually confirm the PDF actually opens**

Run:
```bash
mix run -e '
doc = Press.PDF.Document.new()
{doc, page} = Press.PDF.Document.add_page(doc, 595.0, 842.0)

doc =
  doc
  |> Press.PDF.Document.draw_rect(page, 50.0, 700.0, 200.0, 80.0, fill: {0.9, 0.9, 0.9}, stroke: {0, 0, 0}, stroke_width: 1.0)
  |> Press.PDF.Document.draw_text(page, 60.0, 750.0, "Hello world!", font: :helvetica_bold, size: 24)

File.write!("/tmp/press_hello.pdf", Press.PDF.Writer.to_binary(doc))
'
open /tmp/press_hello.pdf
```

Expected: your system PDF viewer opens `/tmp/press_hello.pdf` and shows a light-gray bordered box with bold "Hello world!" text inside it, on an A4-sized page. This is the real acceptance check for Phase 1 — the automated tests check structure, this confirms it's an actual usable PDF.

- [x] **Step 4: Commit**

```bash
git add test/press/pdf/integration_test.exs
git commit -m "Add end-to-end integration test for PDF writer core"
```

---

## Definition of Done

- [x] All tasks above complete, all tests passing (`mix test`).
- [x] The manual check in Task 6 Step 3 confirms a real PDF viewer opens the generated file correctly.
- [x] `docs/superpowers/plans/2026-07-21-pdf-writer-core.md` (this file) has every checkbox ticked.
- [ ] Next phase (Phase 2 — HTML parser, per `docs/superpowers/specs/2026-07-20-html-css-to-pdf-design.md`) gets its own plan document when it's time to start it.
