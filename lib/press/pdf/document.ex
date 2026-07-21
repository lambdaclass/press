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
    if index < 0 or index >= length(pages) do
      raise ArgumentError, "no page at index #{index} (document has #{length(pages)} page(s))"
    end

    %{doc | pages: List.update_at(pages, index, fun)}
  end
end
