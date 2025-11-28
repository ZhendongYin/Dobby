defmodule Dobby.Uploads.ImageProcessor do
  @moduledoc """
  Handles image processing (resize, crop, optimize).
  """

  @doc """
  Processes an image file: resizes and optimizes it.

  Options:
  - `:width` - target width (default: nil, keep original)
  - `:height` - target height (default: nil, keep original)
  - `:quality` - JPEG quality 0-100 (default: 85)
  - `:format` - output format: :jpeg, :png (default: :jpeg)
  """
  def process_image(file_path, opts \\ []) do
    width = Keyword.get(opts, :width)
    height = Keyword.get(opts, :height)
    quality = Keyword.get(opts, :quality, 85)
    format = Keyword.get(opts, :format, :jpeg)

    try do
      image = Mogrify.open(file_path)

      image =
        cond do
          width && height ->
            image
            |> Mogrify.resize("#{width}x#{height}")
            |> Mogrify.quality(quality)
            |> Mogrify.format(to_string(format))

          width ->
            image
            |> Mogrify.resize("#{width}x")
            |> Mogrify.quality(quality)
            |> Mogrify.format(to_string(format))

          height ->
            image
            |> Mogrify.resize("x#{height}")
            |> Mogrify.quality(quality)
            |> Mogrify.format(to_string(format))

          true ->
            image
            |> Mogrify.quality(quality)
            |> Mogrify.format(to_string(format))
        end

      image = Mogrify.save(image)

      {:ok, image.path}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Gets image dimensions.
  """
  def get_image_info(file_path) do
    try do
      image = Mogrify.open(file_path)
      {:ok, image.width, image.height, image.format}
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end
