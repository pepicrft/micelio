defmodule Micelio.Storage do
  @moduledoc """
  Storage abstraction for session files and artifacts.

  By default uses local filesystem storage. Can be configured to use S3 or the
  tiered cache backend.

  Configuration via `config/runtime.exs`:
      STORAGE_BACKEND=local|s3|tiered
      STORAGE_LOCAL_PATH=/var/micelio/storage  # defaults to /var/micelio/storage in prod or <tmp>/micelio/storage in dev/test
      S3_BUCKET=micelio-sessions
      S3_REGION=us-east-1
      STORAGE_CACHE_PATH=/var/micelio/cache
      STORAGE_CDN_BASE_URL=https://cdn.example.com/micelio
  """

  @doc """
  Stores a file and returns its key/path.
  """
  def put(key, content) do
    backend().put(key, content)
  end

  @doc """
  Retrieves a file by key.
  """
  def get(key) do
    backend().get(key)
  end

  @doc """
  Retrieves a file with storage metadata (e.g., ETag).
  """
  def get_with_metadata(key) do
    backend().get_with_metadata(key)
  end

  @doc """
  Deletes a file by key.
  """
  def delete(key) do
    backend().delete(key)
  end

  @doc """
  Lists files with a given prefix.
  """
  def list(prefix) do
    backend().list(prefix)
  end

  @doc """
  Checks if a file exists.
  """
  def exists?(key) do
    backend().exists?(key)
  end

  @doc """
  Returns a CDN URL for the given key when configured.

  Returns nil when no CDN base URL is configured.
  """
  def cdn_url(key) when is_binary(key) do
    # Check process dictionary first (for test isolation)
    # Then fall back to Application config
    config =
      Process.get(:micelio_storage_config) ||
        Application.get_env(:micelio, __MODULE__, [])

    case Keyword.get(config, :cdn_base_url) do
      base when is_binary(base) and base != "" ->
        base = String.trim_trailing(base, "/")
        "#{base}/#{encode_cdn_key(key)}"

      _ ->
        nil
    end
  end

  @doc """
  Returns metadata for a key when available (e.g., ETag).
  """
  def head(key) do
    backend().head(key)
  end

  @doc """
  Stores a file only if the current ETag matches.
  """
  def put_if_match(key, content, etag) do
    backend().put_if_match(key, content, etag)
  end

  @doc """
  Stores a file only if it does not already exist.
  """
  def put_if_none_match(key, content) do
    backend().put_if_none_match(key, content)
  end

  defp backend do
    # Check process dictionary first (for test isolation)
    # Then fall back to Application config
    config =
      Process.get(:micelio_storage_config) ||
        Application.get_env(:micelio, __MODULE__, [])

    backend_type = Keyword.get(config, :backend, :local)

    case backend_type do
      :local -> Micelio.Storage.Local
      :s3 -> Micelio.Storage.S3
      :tiered -> Micelio.Storage.Tiered
    end
  end

  defp encode_cdn_key(key) when is_binary(key) do
    key
    |> String.split("/", trim: false)
    |> Enum.map_join("/", fn segment ->
      URI.encode(segment, fn ch -> URI.char_unreserved?(ch) end)
    end)
  end
end
