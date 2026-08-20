defmodule Press do
  @moduledoc """
  `Press` is a dependency-free, pure-Elixir HTML+CSS to PDF engine.
  """

  alias Press.CSS.Parser, as: CSSParser
  alias Press.HTML.Element
  alias Press.HTML.Parser, as: HTMLParser
  alias Press.Layout
  alias Press.Layout.Paginate
  alias Press.PDF.{Renderer, Writer}
  alias Press.Style.Cascade

  @doc """
  Renders an HTML string with optional CSS and options into a PDF binary.

  ## Options

  - `:css` — external CSS string applied before embedded `<style>` blocks.
  - `:images` — a map of `%{src => binary_data}` for image references.

  ## Examples

      iex> {:ok, pdf} = Press.render("<h1>Invoice #123</h1>")
      iex> is_binary(pdf)
      true

  """
  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def render(html, opts \\ []) when is_binary(html) and is_list(opts) do
    external_css = Keyword.get(opts, :css, "")
    images = Keyword.get(opts, :images, %{})

    # 1. Parse HTML
    dom = HTMLParser.parse(html)

    # 2. Extract embedded <style>
    embedded_css = extract_style_content(dom)

    # 3. Parse CSS
    {ext_page_rules, ext_style_rules} = CSSParser.parse(external_css || "")
    {emb_page_rules, emb_style_rules} = CSSParser.parse(embedded_css)

    # 4. Cascade & Page Config
    page_config = Cascade.page_config(ext_page_rules, emb_page_rules)
    styled_tree = Cascade.build(dom, ext_style_rules, emb_style_rules)

    # 5. Layout
    root_box = Layout.build(styled_tree, page_config, images)

    # 6. Pagination
    pages = Paginate.paginate(root_box, page_config)

    # 7. Render to PDF Document
    doc = Renderer.render_document(pages, page_config)

    # 8. Write PDF Binary
    pdf_bytes = Writer.to_binary(doc)

    {:ok, pdf_bytes}
  end

  defp extract_style_content(nodes) do
    nodes
    |> find_all_tag("style")
    |> Enum.map_join("\n", fn %Element{children: children} ->
      Enum.map_join(children, "", fn
        %Press.HTML.Text{content: c} -> c
        _ -> ""
      end)
    end)
  end

  defp find_all_tag(nodes, tag) do
    Enum.flat_map(nodes, fn
      %Element{tag: ^tag} = el -> [el]
      %Element{children: children} -> find_all_tag(children, tag)
      _ -> []
    end)
  end
end
