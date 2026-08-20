defmodule Press.CSS.DefaultStylesheet do
  @moduledoc false

  alias Press.CSS.Parser

  @css """
  strong, b { font-weight: bold; }
  em, i { font-style: italic; }
  th { font-weight: bold; text-align: center; }
  h1 { font-size: 24pt; margin: 0.67em 0; }
  h2 { font-size: 18pt; margin: 0.75em 0; }
  h3 { font-size: 14pt; margin: 0.83em 0; }
  h4 { font-size: 12pt; margin: 1.12em 0; }
  h5 { font-size: 10pt; margin: 1.5em 0; }
  h6 { font-size: 8pt; margin: 1.67em 0; }
  p { margin: 1em 0; }
  ul, ol { list-style-position: outside; margin: 1em 0; }
  ul { list-style-type: disc; }
  ol { list-style-type: decimal; }
  """

  {parsed_page_rules, parsed_style_rules} = Parser.parse(@css)
  @parsed_page_rules parsed_page_rules
  @parsed_style_rules parsed_style_rules

  def rules, do: @parsed_style_rules
  def page_rules, do: @parsed_page_rules
end
