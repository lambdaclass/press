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
  - `:embed_fonts` — a map of `%{font => path_or_binary}` naming font files to
    carry inside the PDF, e.g. `%{helvetica: "…/Regular.otf", helvetica_bold:
    "…/Bold.otf"}`. Without it the PDF asks for the 14 base fonts and the
    reader supplies them, so the letterforms depend on the reader; with it the
    document is self-contained and renders the same everywhere. The file has to
    be metrically compatible with the base font it replaces, since layout was
    already measured against the base metrics.
  - `:bold_boost` — synthesises a heavier bold by stroking the glyphs, as a
    fraction of the font size (e.g. `0.02`). The base-14 fonts stop at
    Helvetica-Bold, so this is the only way to reach the weight of a heavier
    face. Defaults to `0.0`, which leaves the bold face untouched.
  - `:page` — overrides the `@page` rule. `size:` takes `{width_pt, height_pt}` or
    `:a4` / `:letter` / `:legal`, and `landscape: true` swaps the resolved pair.
    `margin:` takes a number of points for all four sides, or a map with any of
    `:top`, `:right`, `:bottom`, `:left`. Given as render options so a caller
    driving page setup programmatically does not have to synthesise CSS.

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
    page_config =
      Cascade.page_config(ext_page_rules, emb_page_rules)
      |> apply_page_overrides(Keyword.get(opts, :page, []))
      |> Map.put(:embedded_fonts, load_fonts(Keyword.get(opts, :embed_fonts, %{})))
    styled_tree = Cascade.build(dom, ext_style_rules, emb_style_rules)

    # 5. Layout
    root_box = Layout.build(styled_tree, page_config, images)

    # 6. Pagination
    pages = Paginate.paginate(root_box, page_config)

    # 7. Render to PDF Document
    doc =
      Renderer.render_document(
        pages,
        Map.put(page_config, :bold_boost, Keyword.get(opts, :bold_boost, 0.0))
      )

    # 8. Write PDF Binary
    pdf_bytes = Writer.to_binary(doc)

    {:ok, pdf_bytes}
  end

  @doc """
  Renders an HTML string into a PDF binary, raising on error.

  Same as `render/2`, but returns the PDF binary directly or raises a `RuntimeError`
  if rendering fails.

  ## Examples

      iex> pdf = Press.render!("<h1>Invoice #123</h1>")
      iex> is_binary(pdf)
      true

  """
  @spec render!(String.t(), keyword()) :: binary()
  def render!(html, opts \\ []) when is_binary(html) and is_list(opts) do
    case render(html, opts) do
      {:ok, pdf_bytes} -> pdf_bytes
      {:error, reason} -> raise "failed to render PDF: #{inspect(reason)}"
    end
  end

  # A font that cannot be read is skipped rather than fatal: the reader's own
  # base font still draws the page, so a missing file degrades the letterforms
  # instead of losing the document.
  defp load_fonts(sources) do
    Map.new(sources, fn {font, source} ->
      case Press.Font.Program.load(source) do
        {:ok, program} -> {font, program}
        {:error, _reason} -> {font, nil}
      end
    end)
    |> Enum.reject(fn {_font, program} -> is_nil(program) end)
    |> Map.new()
  end

  @named_sizes %{a4: {595.28, 841.89}, letter: {612.0, 792.0}, legal: {612.0, 1008.0}}

  defp apply_page_overrides(config, []), do: config

  defp apply_page_overrides(config, opts) do
    config
    |> override_size(Keyword.get(opts, :size), Keyword.get(opts, :landscape, false))
    |> override_margin(Keyword.get(opts, :margin))
  end

  defp override_size(config, nil, landscape), do: maybe_landscape(config, landscape)

  defp override_size(config, {w, h}, landscape) when is_number(w) and is_number(h) do
    maybe_landscape(%{config | size: {w * 1.0, h * 1.0}}, landscape)
  end

  defp override_size(config, name, landscape) when is_atom(name) do
    case Map.fetch(@named_sizes, name) do
      {:ok, size} -> maybe_landscape(%{config | size: size}, landscape)
      :error -> maybe_landscape(config, landscape)
    end
  end

  defp maybe_landscape(config, true) do
    {w, h} = config.size
    %{config | size: {max(w, h), min(w, h)}}
  end

  defp maybe_landscape(config, _), do: config

  defp override_margin(config, nil), do: config

  defp override_margin(config, pt) when is_number(pt) do
    %{config | margin: %{top: pt * 1.0, right: pt * 1.0, bottom: pt * 1.0, left: pt * 1.0}}
  end

  defp override_margin(config, %{} = sides) do
    %{config | margin: Map.merge(config.margin, Map.new(sides, fn {k, v} -> {k, v * 1.0} end))}
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
