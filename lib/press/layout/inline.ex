defmodule Press.Layout.Inline do
  @moduledoc false

  alias Press.Font.Metrics
  alias Press.Layout.Box
  alias Press.Style.{Node, Text}

  @doc """
  Takes a list of inline nodes (Text or inline Element Nodes), available width,
  and text-align (:left | :center | :right), and returns a list of positioned
  `:line` Box structs.
  """
  def wrap(nodes, available_width, text_align \\ :left) do
    tokens =
      nodes
      |> flatten_inlines()
      |> collapse_whitespace()

    # `white-space: nowrap` keeps the run on one line even when it overflows,
    # which is the point of asking for it.
    lines =
      if nowrap?(nodes) do
        [drop_leading_spaces(tokens)]
      else
        break_lines(tokens, available_width)
      end

    Enum.map(lines, &build_line_box(&1, available_width, text_align))
  end

  defp nowrap?(nodes) do
    Enum.any?(nodes, fn
      %Node{computed: %{white_space: ws}} -> ws in [:nowrap, :pre]
      %Text{computed: %{white_space: ws}} -> ws in [:nowrap, :pre]
      _ -> false
    end)
  end

  defp flatten_inlines(nodes) do
    Enum.flat_map(nodes, &flatten_node/1)
  end

  defp flatten_node(%Text{content: content, computed: computed}) do
    tokenize_text(content, computed)
  end

  defp flatten_node(%Node{children: children}) do
    flatten_inlines(children)
  end

  defp tokenize_text(content, computed) do
    font = Metrics.font_for(computed.font_family, computed.font_weight, computed.font_style)
    font_size = computed.font_size
    line_height = computed.line_height
    color = computed.color
    tracking = Map.get(computed, :letter_spacing, 0.0)

    Regex.scan(~r/\S+|\s+/, content)
    |> List.flatten()
    |> Enum.map(fn token ->
      if String.trim(token) == "" do
        space_width = Metrics.text_width(font, " ", font_size, tracking)

        %{
          type: :space,
          text: " ",
          font: font,
          font_size: font_size,
          line_height: line_height,
          color: color,
          letter_spacing: tracking,
          width: space_width
        }
      else
        word_width = Metrics.text_width(font, token, font_size, tracking)

        %{
          type: :word,
          text: token,
          font: font,
          font_size: font_size,
          line_height: line_height,
          color: color,
          letter_spacing: tracking,
          width: word_width
        }
      end
    end)
  end

  defp collapse_whitespace(tokens) do
    tokens
    |> Enum.reduce([], fn token, acc ->
      case {token.type, acc} do
        {:space, [%{type: :space} | _]} -> acc
        _ -> [token | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp break_lines(tokens, available_width) do
    trimmed_tokens = drop_leading_spaces(tokens)
    do_break_lines(trimmed_tokens, available_width, [], 0.0, [])
  end

  defp do_break_lines([], _avail_w, [], _line_w, lines_acc) do
    Enum.reverse(lines_acc)
  end

  defp do_break_lines([], _avail_w, current_line, _line_w, lines_acc) do
    trimmed_line = trim_line(Enum.reverse(current_line))
    Enum.reverse([trimmed_line | lines_acc])
  end

  defp do_break_lines([token | rest], avail_w, current_line, line_w, lines_acc) do
    if current_line == [] do
      do_break_lines(rest, avail_w, [token], token.width, lines_acc)
    else
      if line_w + token.width <= avail_w do
        do_break_lines(rest, avail_w, [token | current_line], line_w + token.width, lines_acc)
      else
        trimmed_line = trim_line(Enum.reverse(current_line))
        next_tokens = drop_leading_spaces([token | rest])
        do_break_lines(next_tokens, avail_w, [], 0.0, [trimmed_line | lines_acc])
      end
    end
  end

  defp drop_leading_spaces([%{type: :space} | rest]), do: drop_leading_spaces(rest)
  defp drop_leading_spaces(tokens), do: tokens

  defp trim_line(tokens) do
    tokens
    |> drop_leading_spaces()
    |> Enum.reverse()
    |> drop_leading_spaces()
    |> Enum.reverse()
  end

  defp build_line_box(tokens, available_width, text_align) do
    line_width = Enum.reduce(tokens, 0.0, fn t, acc -> acc + t.width end)
    line_height = Enum.reduce(tokens, 0.0, fn t, acc -> max(acc, t.line_height) end)

    start_x =
      case text_align do
        :center -> max(0.0, (available_width - line_width) / 2.0)
        :right -> max(0.0, available_width - line_width)
        _ -> 0.0
      end

    {text_boxes, _final_x} =
      Enum.reduce(tokens, {[], start_x}, fn token, {acc, curr_x} ->
        box = %Box{
          type: :text,
          x: curr_x,
          y: 0.0,
          width: token.width,
          height: token.line_height,
          text: token.text,
          font: token.font,
          font_size: token.font_size,
          color: token.color,
          letter_spacing: token.letter_spacing
        }

        {[box | acc], curr_x + token.width}
      end)

    %Box{
      type: :line,
      x: 0.0,
      y: 0.0,
      width: line_width,
      height: line_height,
      children: Enum.reverse(text_boxes)
    }
  end
end
