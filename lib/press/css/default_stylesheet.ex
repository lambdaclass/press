defmodule Press.CSS.DefaultStylesheet do
  @moduledoc false

  alias Press.CSS.Parser

  # Mirrors the HTML user-agent stylesheet for the elements Press lays out, so
  # a document written against a browser lands in the same place here. Sizes
  # are relative (`em`) for the same reason they are in a browser: a document
  # that sets `body { font-size }` expects headings to scale with it.
  @css """
  strong, b { font-weight: bold; }
  em, i { font-style: italic; }
  h1 { font-size: 2em; margin: 0.67em 0; font-weight: bold; }
  h2 { font-size: 1.5em; margin: 0.83em 0; font-weight: bold; }
  h3 { font-size: 1.17em; margin: 1em 0; font-weight: bold; }
  h4 { font-size: 1em; margin: 1.33em 0; font-weight: bold; }
  h5 { font-size: 0.83em; margin: 1.67em 0; font-weight: bold; }
  h6 { font-size: 0.67em; margin: 2.33em 0; font-weight: bold; }
  p { margin: 1em 0; }
  ul, ol { list-style-position: outside; margin: 1em 0; padding-left: 40px; }
  ul { list-style-type: disc; }
  ol { list-style-type: decimal; }
  th { font-weight: bold; text-align: center; }
  th, td { padding: 1px; }
  hr { margin: 0.5em 0; border-width: 1px; border-style: solid; }
  table.table-xs th, table.table-xs td { font-size: 9pt; padding: 4pt 8pt; }
  table.table-sm th, table.table-sm td { font-size: 10.5pt; padding: 6pt 10pt; }
  """

  {parsed_page_rules, parsed_style_rules} = Parser.parse(@css)
  @parsed_page_rules parsed_page_rules
  @parsed_style_rules parsed_style_rules

  def rules, do: @parsed_style_rules
  def page_rules, do: @parsed_page_rules
end
