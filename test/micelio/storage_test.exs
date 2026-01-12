defmodule Micelio.StorageTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Micelio.Storage

  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    :ok
  end

  describe "backend selection" do
    test "uses local backend when configured" do
      Application.put_env(:micelio, Micelio.Storage, backend: :local)

      # Should use local storage
      key = "test/local.txt"
      content = "local content"

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)

      # Cleanup
      Storage.delete(key)
    end

    test "uses S3 backend when configured" do
      Application.put_env(:micelio, Micelio.Storage,
        backend: :s3,
        s3_bucket: "test-bucket",
        s3_region: "us-east-1",
        s3_access_key_id: "test-key",
        s3_secret_access_key: "test-secret"
      )

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
      Application.delete_env(:micelio, Micelio.Storage)

      # Should default to local
      key = "test/default.txt"
      content = "default content"

      {:ok, ^key} = Storage.put(key, content)
      {:ok, ^content} = Storage.get(key)

      # Cleanup
      Storage.delete(key)
    end
  end
end
