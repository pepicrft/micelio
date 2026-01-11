defmodule Micelio.Storage.Local do
  @moduledoc """
  Local filesystem storage backend.
  
  Stores files in a local directory structure.
  """

  @doc """
  Stores content at the given key.
  """
  def put(key, content) do
    path = build_path(key)
    
    with :ok <- ensure_directory(path),
         :ok <- File.write(path, content) do
      {:ok, key}
    end
  end

  @doc """
  Retrieves content by key.
  """
  def get(key) do
    path = build_path(key)
    
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Deletes a file by key.
  """
  def delete(key) do
    path = build_path(key)
    
    case File.rm(path) do
      :ok -> {:ok, key}
      {:error, :enoent} -> {:ok, key}
      error -> error
    end
  end

  @doc """
  Lists files with the given prefix.
  """
  def list(prefix) do
    base_path = base_path()
    pattern = Path.join([base_path, prefix, "**", "*"])
    
    files =
      pattern
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        String.replace_prefix(path, base_path <> "/", "")
      end)
    
    {:ok, files}
  end

  @doc """
  Checks if a file exists.
  """
  def exists?(key) do
    path = build_path(key)
    File.exists?(path)
  end

  defp build_path(key) do
    Path.join(base_path(), key)
  end

  defp base_path do
    config = Application.get_env(:micelio, Micelio.Storage, [])
    Keyword.get(config, :local_path, default_path())
  end

  defp default_path do
    Path.join([System.tmp_dir!(), "micelio", "storage"])
  end

  defp ensure_directory(file_path) do
    file_path
    |> Path.dirname()
    |> File.mkdir_p()
  end
end
