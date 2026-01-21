defmodule Micelio.StorageHelper do
  @moduledoc """
  Test helper for creating isolated storage configurations.

  This module enables tests to run in parallel by providing isolated
  storage directories instead of relying on global Application config.

  ## Usage

      setup do
        {:ok, storage} = StorageHelper.create_isolated_storage()
        
        on_exit(fn ->
          StorageHelper.cleanup(storage)
        end)

        {:ok, storage: storage}
      end

      test "something with storage", %{storage: storage} do
        StorageHelper.with_config(storage, fn ->
          # Code that uses Micelio.Storage will use isolated config
          Micelio.Storage.put("key", "value")
        end)
      end
  """

  @doc """
  Creates an isolated storage configuration for testing.

  Returns a map with:
  - `:config` - Keyword list config to pass to Storage functions
  - `:path` - The storage directory path
  - `:base_dir` - The base temp directory (for cleanup)
  """
  def create_isolated_storage(opts \\ []) do
    unique = System.unique_integer([:positive])
    base = Keyword.get(opts, :base_dir, System.tmp_dir!())
    base_dir = Path.join([base, "micelio-test-#{unique}"])
    storage_dir = Path.join(base_dir, "storage")

    File.mkdir_p!(storage_dir)

    config = [backend: :local, local_path: storage_dir]

    {:ok, %{config: config, path: storage_dir, base_dir: base_dir}}
  end

  @doc """
  Cleans up an isolated storage created by `create_isolated_storage/1`.
  """
  def cleanup(%{base_dir: base_dir}) do
    # Use rm_rf (without !) to gracefully handle cases where background
    # processes may still be writing to the directory
    case File.rm_rf(base_dir) do
      {:ok, _} -> :ok
      # File.rm_rf returns {:error, reason, file} on failure
      {:error, _reason, _file} -> :ok
    end
  end

  def cleanup(_), do: :ok

  @doc """
  Executes a function with isolated storage config set in the process dictionary.

  This allows existing code that reads from Application config to transparently
  use the isolated config during the function execution.

  ## Example

      StorageHelper.with_config(storage, fn ->
        # Micelio.Storage will use isolated config
        Micelio.Storage.put("test.txt", "content")
      end)
  """
  def with_config(%{config: config}, fun) when is_function(fun, 0) do
    with_config(config, fun)
  end

  def with_config(config, fun) when is_list(config) and is_function(fun, 0) do
    previous = Process.get(:micelio_storage_config)
    Process.put(:micelio_storage_config, config)

    try do
      fun.()
    after
      if previous do
        Process.put(:micelio_storage_config, previous)
      else
        Process.delete(:micelio_storage_config)
      end
    end
  end

  @doc """
  Sets up isolated storage for the test process and registers cleanup.

  Use in a `setup` block:

      setup context do
        StorageHelper.setup_isolated_storage(context)
      end

  Returns `{:ok, storage_config: config}` to merge into test context.
  """
  def setup_isolated_storage(_context \\ %{}) do
    {:ok, storage} = create_isolated_storage()

    ExUnit.Callbacks.on_exit(fn ->
      cleanup(storage)
    end)

    # Also set in process dictionary for transparent use
    Process.put(:micelio_storage_config, storage.config)

    {:ok, storage_config: storage.config, storage_path: storage.path}
  end

  @doc """
  Creates isolated storage and configures Application env (for tests that can't be refactored yet).

  **Note**: This still uses global state - prefer `with_config/2` for new tests.
  """
  def setup_isolated_storage_with_app_env(_context \\ %{}) do
    {:ok, storage} = create_isolated_storage()

    previous = Application.get_env(:micelio, Micelio.Storage)
    Application.put_env(:micelio, Micelio.Storage, storage.config)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Micelio.Storage)
        _ -> Application.put_env(:micelio, Micelio.Storage, previous)
      end

      cleanup(storage)
    end)

    {:ok, storage_config: storage.config, storage_path: storage.path}
  end
end
