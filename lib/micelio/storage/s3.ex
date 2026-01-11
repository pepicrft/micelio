defmodule Micelio.Storage.S3 do
  @moduledoc """
  S3 storage backend (opt-in).
  
  To use S3 storage, configure:
  
      config :micelio, Micelio.Storage,
        backend: :s3,
        s3_bucket: "your-bucket-name",
        s3_region: "us-east-1",
        s3_access_key_id: "your-access-key",
        s3_secret_access_key: "your-secret-key"
  
  Or use IAM roles/instance profiles for AWS credentials.
  """

  @doc """
  Stores content at the given key in S3.
  """
  def put(key, content) do
    # TODO: Implement S3 upload using ex_aws or similar
    # For now, fall back to local storage
    require Logger
    Logger.warning("S3 storage not yet implemented, falling back to local")
    Micelio.Storage.Local.put(key, content)
  end

  @doc """
  Retrieves content by key from S3.
  """
  def get(key) do
    # TODO: Implement S3 download
    require Logger
    Logger.warning("S3 storage not yet implemented, falling back to local")
    Micelio.Storage.Local.get(key)
  end

  @doc """
  Deletes a file by key from S3.
  """
  def delete(key) do
    # TODO: Implement S3 delete
    require Logger
    Logger.warning("S3 storage not yet implemented, falling back to local")
    Micelio.Storage.Local.delete(key)
  end

  @doc """
  Lists files with the given prefix in S3.
  """
  def list(prefix) do
    # TODO: Implement S3 list
    require Logger
    Logger.warning("S3 storage not yet implemented, falling back to local")
    Micelio.Storage.Local.list(prefix)
  end

  @doc """
  Checks if a file exists in S3.
  """
  def exists?(key) do
    # TODO: Implement S3 exists check
    require Logger
    Logger.warning("S3 storage not yet implemented, falling back to local")
    Micelio.Storage.Local.exists?(key)
  end
end
