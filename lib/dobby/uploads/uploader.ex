defmodule Dobby.Uploads.Uploader do
  @moduledoc """
  Handles file uploads to S3 or local storage (for development).
  """

  alias ExAws.S3

  @doc """
  Uploads a file to S3 or local storage (in development).

  Returns `{:ok, url}` on success, `{:error, reason}` on failure.
  """
  def upload_file(file_path, s3_path, opts \\ []) when is_binary(file_path) do
    if use_local_storage?() do
      upload_to_local(file_path, s3_path)
    else
      upload_to_s3(file_path, s3_path, opts)
    end
  end

  defp upload_to_s3(file_path, s3_path, opts) do
    bucket = Keyword.get(opts, :bucket, bucket_name())
    region = Keyword.get(opts, :region, region())

    file_content = File.read!(file_path)
    content_type = detect_content_type(file_path)

    bucket
    |> S3.put_object(s3_path, file_content, content_type: content_type)
    |> ExAws.request(region: region)
    |> case do
      {:ok, _} ->
        url = build_url(bucket, s3_path, region)
        {:ok, url}

      error ->
        error
    end
  end

  defp upload_to_local(file_path, relative_path) do
    # Create uploads directory if it doesn't exist
    uploads_dir = Path.join([:code.priv_dir(:dobby), "static", "uploads"])
    File.mkdir_p!(uploads_dir)

    # Build destination path
    dest_path = Path.join(uploads_dir, relative_path)
    dest_dir = Path.dirname(dest_path)
    File.mkdir_p!(dest_dir)

    # Copy file to destination
    case File.copy(file_path, dest_path) do
      {:ok, _} ->
        # Return URL path for local storage
        url = "/uploads/#{relative_path}"
        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Uploads file content directly to S3.
  """
  def upload_content(content, path, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, bucket_name())
    region = Keyword.get(opts, :region, region())
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    bucket
    |> S3.put_object(path, content, content_type: content_type)
    |> ExAws.request(region: region)
    |> case do
      {:ok, _} ->
        url = build_url(bucket, path, region)
        {:ok, url}

      error ->
        error
    end
  end

  @doc """
  Deletes a file from S3.
  """
  def delete_file(path, opts \\ []) do
    bucket = Keyword.get(opts, :bucket, bucket_name())
    region = Keyword.get(opts, :region, region())

    bucket
    |> S3.delete_object(path)
    |> ExAws.request(region: region)
  end

  defp bucket_name do
    Application.get_env(:dobby, :s3_bucket) || System.get_env("S3_BUCKET") || "dobby-uploads"
  end

  defp region do
    Application.get_env(:dobby, :aws_region) || System.get_env("AWS_REGION") || "us-east-1"
  end

  defp build_url(bucket, path, region) do
    # Use CloudFront URL if configured, otherwise use S3 URL
    cloudfront_url =
      Application.get_env(:dobby, :cloudfront_url) || System.get_env("CLOUDFRONT_URL")

    if cloudfront_url do
      "#{cloudfront_url}/#{path}"
    else
      "https://#{bucket}.s3.#{region}.amazonaws.com/#{path}"
    end
  end

  defp detect_content_type(file_path) do
    case Path.extname(file_path) do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  defp use_local_storage? do
    # Use local storage if S3 credentials are not configured
    # This works in all environments (dev, test, prod)
    not s3_configured?()
  end

  defp s3_configured? do
    # Check if AWS credentials are configured
    aws_access_key =
      System.get_env("AWS_ACCESS_KEY_ID") || Application.get_env(:ex_aws, :access_key_id)

    aws_secret_key =
      System.get_env("AWS_SECRET_ACCESS_KEY") || Application.get_env(:ex_aws, :secret_access_key)

    not is_nil(aws_access_key) and not is_nil(aws_secret_key)
  end
end
