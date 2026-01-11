defmodule Micelio.Storage do
  @moduledoc """
  Storage abstraction for session files and artifacts.
  
  By default uses local filesystem storage. Can be configured to use S3.
  
  Configuration:
      config :micelio, Micelio.Storage,
        backend: :local,  # or :s3
        local_path: "/var/micelio/storage",
        s3_bucket: "micelio-sessions",
        s3_region: "us-east-1"
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

  defp backend do
    config = Application.get_env(:micelio, __MODULE__, [])
    backend_type = Keyword.get(config, :backend, :local)

    case backend_type do
      :local -> Micelio.Storage.Local
      :s3 -> Micelio.Storage.S3
    end
  end
end
