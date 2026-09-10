defmodule Press.Layout.Image do
  @moduledoc false

  alias Press.Image
  alias Press.Image.Parser, as: ImageParser
  alias Press.Layout.Box
  alias Press.Style.Node

  @doc """
  Lays out an <img> element node.
  Returns `{box, next_y, margin_bottom}`.
  """
  def layout_image(
        %Node{element: %{tag: "img", attrs: attrs}} = node,
        images,
        containing_width,
        container_x,
        start_y
      ) do
    computed = node.computed
    src = Map.get(attrs, "src", "")

    case ImageParser.load(src, images) do
      {:ok, %Image{} = image} ->
        image_with_id =
          if image.id do
            image
          else
            %{image | id: "img_#{:erlang.unique_integer([:positive])}"}
          end

        intrinsic_w = image.width * 0.75
        intrinsic_h = image.height * 0.75

        margin = resolve_box_dimensions(computed.margin, containing_width)
        padding = resolve_box_dimensions(computed.padding, containing_width)
        border_width = resolve_box_dimensions(computed.border_width, containing_width)

        spec_w = resolve_img_dim(Map.get(attrs, "width"), computed.width, containing_width)
        spec_h = resolve_img_dim(Map.get(attrs, "height"), computed.height, containing_width)

        {content_w, content_h} =
          case {spec_w, spec_h} do
            {w, h} when is_number(w) and is_number(h) ->
              {w, h}

            {w, nil} when is_number(w) ->
              {w, if(intrinsic_w > 0, do: w / intrinsic_w * intrinsic_h, else: intrinsic_h)}

            {nil, h} when is_number(h) ->
              {if(intrinsic_h > 0, do: h / intrinsic_h * intrinsic_w, else: intrinsic_w), h}

            _ ->
              {intrinsic_w, intrinsic_h}
          end

        # An image is inline-level, so the containing block's `text-align`
        # places it just as it would a word.
        outer_w =
          content_w + padding.left + padding.right + border_width.left + border_width.right +
            margin.left + margin.right

        # `text-align` inherits, so the image already carries its containing
        # block's value.
        box_x =
          container_x + margin.left +
            align_offset(Map.get(computed, :text_align, :left), containing_width, outer_w)
        box_y = start_y + margin.top

        total_outer_height =
          content_h + padding.top + padding.bottom + border_width.top + border_width.bottom

        box = %Box{
          type: :image,
          tag: "img",
          x: box_x,
          y: box_y,
          width: content_w,
          height: content_h,
          image: image_with_id,
          margin: margin,
          padding: padding,
          border_width: border_width,
          border_color: computed.border_color,
          border_style: computed.border_style,
          background_color: computed.background_color,
          computed: computed
        }

        next_y = box_y + total_outer_height
        {box, next_y, margin.bottom}

      {:error, _} ->
        box = %Box{
          type: :image,
          tag: "img",
          x: container_x,
          y: start_y,
          width: 0.0,
          height: 0.0
        }

        {box, start_y, 0.0}
    end
  end

  defp align_offset(:center, containing_width, outer_w),
    do: max(0.0, (containing_width - outer_w) / 2.0)

  defp align_offset(:right, containing_width, outer_w),
    do: max(0.0, containing_width - outer_w)

  defp align_offset(_text_align, _containing_width, _outer_w), do: 0.0

  defp resolve_img_dim(attr, computed_val, containing_width) do
    cond do
      is_binary(attr) and attr != "" ->
        case Float.parse(attr) do
          {val, "pt"} -> val
          {val, "px"} -> val * 0.75
          {val, ""} -> val * 0.75
          _ -> nil
        end

      is_number(computed_val) ->
        computed_val * 1.0

      match?({:percent, _}, computed_val) ->
        {:percent, p} = computed_val
        p / 100.0 * containing_width

      true ->
        nil
    end
  end

  defp resolve_box_dimensions(map, containing_width) do
    Map.new(map, fn {k, v} ->
      val =
        case v do
          {:percent, p} -> p / 100.0 * containing_width
          n when is_number(n) -> n * 1.0
          _ -> 0.0
        end

      {k, val}
    end)
  end
end
