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
    config = Application.get_env(:micelio, __MODULE__, [])
    backend_type = Keyword.get(config, :backend, :local)

    case backend_type do
      :local -> Micelio.Storage.Local
      :s3 -> Micelio.Storage.S3
      :tiered -> Micelio.Storage.Tiered
    end
  end
end
