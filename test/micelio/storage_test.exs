defmodule Micelio.StorageTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Micelio.Storage
  alias Micelio.StorageHelper

  setup :verify_on_exit!
  setup :set_mimic_private

  setup do
    Mimic.copy(Req)
    :ok
  end

  describe "backend selection" do
    test "uses local backend when configured" do
      # Use isolated storage via process dictionary
      {:ok, storage} = StorageHelper.create_isolated_storage()
      Process.put(:micelio_storage_config, storage.config)

      on_exit(fn ->
        Process.delete(:micelio_storage_config)
        StorageHelper.cleanup(storage)
      end)

      key = "test/local.txt"
      content = "local content"

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)

      # Cleanup
      Storage.delete(key)
    end

    test "uses S3 backend when configured" do
      # Configure S3 backend via process dictionary
      config = [
        backend: :s3,
        s3_bucket: "test-bucket",
        s3_region: "us-east-1",
        s3_access_key_id: "test-key",
        s3_secret_access_key: "test-secret"
      ]

      Process.put(:micelio_storage_config, config)

      on_exit(fn ->
        Process.delete(:micelio_storage_config)
      end)

      key = "test/s3.txt"
      content = "s3 content"

      # Mock S3 PUT
      expect(Req, :request, fn opts ->
        assert opts[:method] == :put
        {:ok, %{status: 200, body: ""}}
      end)

      # Mock S3 GET
      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        {:ok, %{status: 200, body: content}}
      end)

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)
    end

    test "defaults to local backend when not configured" do
      # Ensure process dictionary is clear to test default behavior
      Process.delete(:micelio_storage_config)

      # Create a temp directory for this test
      unique = System.unique_integer([:positive])
      tmp_dir = Path.join(System.tmp_dir!(), "micelio-default-test-#{unique}")

      on_exit(fn ->
        File.rm_rf(tmp_dir)
      end)

      # The default local backend uses a temp directory
      key = "test/default.txt"
      content = "default content"

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)

      # Cleanup
      Storage.delete(key)
    end

    test "uses tiered backend when configured" do
      unique = Integer.to_string(:erlang.unique_integer([:positive]))
      origin_dir = Path.join(System.tmp_dir!(), "micelio-test-origin-#{unique}")
      cache_dir = Path.join(System.tmp_dir!(), "micelio-test-cache-#{unique}")

      on_exit(fn ->
        Process.delete(:micelio_storage_config)
        File.rm_rf(origin_dir)
        File.rm_rf(cache_dir)
      end)

      # Configure tiered backend via process dictionary
      config = [
        backend: :tiered,
        origin_backend: :local,
        origin_local_path: origin_dir,
        cache_disk_path: cache_dir,
        cache_memory_max_bytes: 1_000_000,
        cache_namespace: "storage-test-#{unique}"
      ]

      Process.put(:micelio_storage_config, config)

      key = "test/tiered.txt"
      content = "tiered content"

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)
      assert File.exists?(Path.join(cache_dir, key))
    end
  end

  describe "cdn_url/1" do
    test "returns a CDN URL when configured" do
      # Configure CDN via process dictionary
      config = [cdn_base_url: "https://cdn.example.test/micelio"]
      Process.put(:micelio_storage_config, config)

      on_exit(fn ->
        Process.delete(:micelio_storage_config)
      end)

      key = "projects/123/blobs/aa/file name.txt"

      assert Storage.cdn_url(key) ==
               "https://cdn.example.test/micelio/projects/123/blobs/aa/file%20name.txt"
    end

    test "returns nil when CDN is not configured" do
      # Configure empty storage config via process dictionary
      Process.put(:micelio_storage_config, [])

      on_exit(fn ->
        Process.delete(:micelio_storage_config)
      end)

      assert Storage.cdn_url("projects/123/blobs/aa/file.txt") == nil
    end
  end
end
