defmodule Press.HTML.Tokenizer do
  @moduledoc false

  alias Press.HTML.Entities

  @style_close ~r/<\/style\s*>/i

  def tokenize(input) when is_binary(input) do
    input
    |> scan_text([])
    |> Enum.reverse()
  end

  # --- Text scanning: look for the next "<" ---

  defp scan_text(input, tokens) do
    case :binary.match(input, "<") do
      :nomatch ->
        emit_text(input, tokens)

      {pos, _len} ->
        text = binary_part(input, 0, pos)
        rest = binary_part(input, pos + 1, byte_size(input) - pos - 1)
        scan_tag_start(rest, emit_text(text, tokens))
    end
  end

  defp emit_text("", tokens), do: tokens

  defp emit_text(text, [{:text, prior} | rest]) do
    [{:text, prior <> Entities.decode(text)} | rest]
  end

  defp emit_text(text, tokens), do: [{:text, Entities.decode(text)} | tokens]

  defp emit_raw_text("", tokens), do: tokens
  defp emit_raw_text(text, tokens), do: [{:text, text} | tokens]

  # --- Right after "<": decide comment / end tag / start tag / literal ---

  defp scan_tag_start("!--" <> rest, tokens), do: skip_comment(rest, tokens)
  defp scan_tag_start("/" <> rest, tokens), do: scan_end_tag(rest, tokens)

  defp scan_tag_start(<<c, _::binary>> = rest, tokens) when c in ?a..?z or c in ?A..?Z do
    scan_start_tag(rest, tokens)
  end

  defp scan_tag_start(rest, tokens) do
    scan_text(rest, emit_text("<", tokens))
  end

  # --- Comments ---

  defp skip_comment(input, tokens) do
    case :binary.match(input, "-->") do
      :nomatch ->
        tokens

      {pos, _len} ->
        rest = binary_part(input, pos + 3, byte_size(input) - pos - 3)
        scan_text(rest, tokens)
    end
  end

  # --- End tags ---

  defp scan_end_tag(input, tokens) do
    case :binary.match(input, ">") do
      :nomatch ->
        tokens

      {pos, _len} ->
        tag = input |> binary_part(0, pos) |> String.trim() |> String.downcase()
        rest = binary_part(input, pos + 1, byte_size(input) - pos - 1)
        tokens = if tag == "", do: tokens, else: [{:end_tag, tag} | tokens]
        scan_text(rest, tokens)
    end
  end

  # --- Start tags ---

  defp scan_start_tag(input, tokens) do
    {tag, rest} = take_tag_name(input, "")
    {attrs, rest} = scan_attributes(rest, %{})

    case rest do
      "" -> tokens
      ">" <> rest -> emit_start_tag(tag, attrs, rest, tokens)
    end
  end

  defp take_tag_name(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?- do
    take_tag_name(rest, acc <> <<c>>)
  end

  defp take_tag_name(rest, acc), do: {String.downcase(acc), rest}

  defp emit_start_tag("style", attrs, rest, tokens) do
    tokens = [{:start_tag, "style", attrs} | tokens]

    case Regex.run(@style_close, rest, return: :index) do
      [{pos, len}] ->
        raw = binary_part(rest, 0, pos)
        after_close = binary_part(rest, pos + len, byte_size(rest) - pos - len)
        tokens = [{:end_tag, "style"} | emit_raw_text(raw, tokens)]
        scan_text(after_close, tokens)

      nil ->
        [{:end_tag, "style"} | emit_raw_text(rest, tokens)]
    end
  end

  defp emit_start_tag(tag, attrs, rest, tokens) do
    scan_text(rest, [{:start_tag, tag, attrs} | tokens])
  end

  # --- Attributes ---

  defp scan_attributes(input, attrs) do
    input = skip_whitespace(input)

    case input do
      "" -> {attrs, ""}
      ">" <> _ = rest -> {attrs, rest}
      "/" <> rest -> scan_attributes(rest, attrs)
      _ -> scan_attribute(input, attrs)
    end
  end

  defp skip_whitespace(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r] do
    skip_whitespace(rest)
  end

  defp skip_whitespace(rest), do: rest

  defp scan_attribute(input, attrs) do
    {name, rest} = take_attr_name(input, "")
    rest = skip_whitespace(rest)

    case rest do
      "=" <> rest ->
        rest = skip_whitespace(rest)
        {value, rest} = take_attr_value(rest)
        scan_attributes(rest, Map.put_new(attrs, name, value))

      _ ->
        scan_attributes(rest, Map.put_new(attrs, name, ""))
    end
  end

  defp take_attr_name(<<c, rest::binary>>, acc)
       when c not in [?\s, ?\t, ?\n, ?\r, ?=, ?/, ?>] do
    take_attr_name(rest, acc <> <<c>>)
  end

  defp take_attr_name(rest, acc), do: {String.downcase(acc), rest}

  defp take_attr_value(<<?", rest::binary>>), do: take_quoted(rest, ?", "")
  defp take_attr_value(<<?', rest::binary>>), do: take_quoted(rest, ?', "")
  defp take_attr_value(rest), do: take_unquoted(rest, "")

  # The repeated `c` requires the extracted byte to equal quote_char — this is how we detect the matching closing quote.
  defp take_quoted(<<c, rest::binary>>, c, acc), do: {Entities.decode(acc), rest}

  defp take_quoted(<<c, rest::binary>>, quote_char, acc) do
    take_quoted(rest, quote_char, acc <> <<c>>)
  end

  defp take_quoted("", _quote_char, acc), do: {Entities.decode(acc), ""}

  defp take_unquoted(<<c, rest::binary>>, acc)
       when c not in [?\s, ?\t, ?\n, ?\r, ?/, ?>] do
    take_unquoted(rest, acc <> <<c>>)
  end

  defp take_unquoted(rest, acc), do: {Entities.decode(acc), rest}
end
