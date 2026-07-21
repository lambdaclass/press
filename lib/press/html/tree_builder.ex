defmodule Press.HTML.TreeBuilder do
  @moduledoc false

  alias Press.HTML.{Element, Text}

  @void_elements ~w(br img link meta)
  @p_closing_tags ~w(p div h1 h2 h3 h4 h5 h6 ul ol table header footer main)
  @sibling_closing_tags ~w(p li tr)
  @cell_tags ~w(td th)

  def build(tokens) do
    {stack, top_level} = Enum.reduce(tokens, {[], []}, &process_token/2)
    {[], top_level} = close_all({stack, top_level})
    Enum.reverse(top_level)
  end

  defp process_token({:text, ""}, state), do: state
  defp process_token({:text, content}, state), do: add_node(state, %Text{content: content})

  defp process_token({:start_tag, tag, attrs}, state) do
    state = autoclose(state, tag)

    if tag in @void_elements do
      add_node(state, %Element{tag: tag, attrs: attrs, children: []})
    else
      {stack, top_level} = state
      {[%{tag: tag, attrs: attrs, children: []} | stack], top_level}
    end
  end

  defp process_token({:end_tag, tag}, {stack, _top_level} = state) do
    if Enum.any?(stack, &(&1.tag == tag)) do
      close_until(state, tag)
    else
      state
    end
  end

  defp autoclose({[%{tag: top_tag} | _], _top_level} = state, new_tag) do
    cond do
      same_tag_sibling?(top_tag, new_tag) ->
        state |> close_top() |> autoclose(new_tag)

      top_tag in @cell_tags and new_tag == "tr" ->
        state |> close_top() |> autoclose(new_tag)

      top_tag == "p" and new_tag in @p_closing_tags ->
        state |> close_top() |> autoclose(new_tag)

      true ->
        state
    end
  end

  defp autoclose(state, _new_tag), do: state

  # Repeated `tag`: matches only when both arguments are the same tag name.
  defp same_tag_sibling?(tag, tag) when tag in @sibling_closing_tags, do: true
  defp same_tag_sibling?(t1, t2) when t1 in @cell_tags and t2 in @cell_tags, do: true
  defp same_tag_sibling?(_t1, _t2), do: false

  # Repeated `tag`: matches only when the top-of-stack frame's tag equals the target.
  defp close_until({[%{tag: tag} | _], _top_level} = state, tag), do: close_top(state)
  defp close_until(state, tag), do: state |> close_top() |> close_until(tag)

  defp close_all({[], top_level}), do: {[], top_level}
  defp close_all(state), do: state |> close_top() |> close_all()

  defp close_top({[frame | rest], top_level}) do
    element = %Element{
      tag: frame.tag,
      attrs: frame.attrs,
      children: Enum.reverse(frame.children)
    }

    add_node({rest, top_level}, element)
  end

  defp add_node({[frame | rest], top_level}, node) do
    {[%{frame | children: [node | frame.children]} | rest], top_level}
  end

  defp add_node({[], top_level}, node), do: {[], [node | top_level]}
end
