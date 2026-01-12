defmodule Micelio.Storage.S3Test do
  use ExUnit.Case, async: false

  import Mimic

  alias Micelio.Storage.S3

  # Copy the module we want to mock
  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    :ok
  end

  describe "put/2" do
    setup do
      setup_s3_config()
      :ok
    end

    test "successfully stores content in S3" do
      content = "test content"
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn opts ->
        assert opts[:method] == :put
        assert opts[:url] =~ "test-bucket"
        assert opts[:url] =~ URI.encode(key, &URI.char_unreserved?/1)
        assert opts[:body] == content
        assert has_auth_headers?(opts[:headers])

        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, ^key} = S3.put(key, content)
    end

    test "returns error on S3 failure" do
      content = "test content"
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 403, body: "Access Denied"}}
      end)

      assert {:error, {:s3_error, 403, "Access Denied"}} = S3.put(key, content)
    end

    test "returns error on network failure" do
      content = "test content"
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:error, :connection_refused}
      end)

      assert {:error, :connection_refused} = S3.put(key, content)
    end

    test "handles special characters in keys" do
      content = "test"
      key = "sessions/test 123/file (1).txt"

      expect(Req, :request, fn opts ->
        # Verify the key is properly encoded
        assert opts[:url] =~ "sessions%2Ftest%20123%2Ffile%20%281%29.txt"
        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, ^key} = S3.put(key, content)
    end
  end

  describe "get/1" do
    setup do
      setup_s3_config()
      :ok
    end

    test "successfully retrieves content from S3" do
      key = "sessions/test123/file.txt"
      content = "stored content"

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ "test-bucket"
        assert opts[:url] =~ URI.encode(key, &URI.char_unreserved?/1)
        assert has_auth_headers?(opts[:headers])

        {:ok, %{status: 200, body: content}}
      end)

      assert {:ok, ^content} = S3.get(key)
    end

    test "returns :not_found when object doesn't exist" do
      key = "sessions/nonexistent/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 404, body: ""}}
      end)

      assert {:error, :not_found} = S3.get(key)
    end

    test "returns error on S3 failure" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      assert {:error, {:s3_error, 500, "Internal Server Error"}} = S3.get(key)
    end
  end

  describe "delete/1" do
    setup do
      setup_s3_config()
      :ok
    end

    test "successfully deletes object from S3" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn opts ->
        assert opts[:method] == :delete
        assert opts[:url] =~ "test-bucket"
        assert opts[:url] =~ URI.encode(key, &URI.char_unreserved?/1)
        {:ok, %{status: 204, body: ""}}
      end)

      assert {:ok, ^key} = S3.delete(key)
    end

    test "returns success even when object doesn't exist (idempotent)" do
      key = "sessions/nonexistent/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 404, body: ""}}
      end)

      assert {:ok, ^key} = S3.delete(key)
    end

    test "returns error on S3 failure" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 403, body: "Access Denied"}}
      end)

      assert {:error, {:s3_error, 403, "Access Denied"}} = S3.delete(key)
    end
  end

  describe "exists?/1" do
    setup do
      setup_s3_config()
      :ok
    end

    test "returns true when object exists" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn opts ->
        assert opts[:method] == :head
        assert opts[:url] =~ "test-bucket"
        assert opts[:url] =~ URI.encode(key, &URI.char_unreserved?/1)
        {:ok, %{status: 200, body: ""}}
      end)

      assert S3.exists?(key) == true
    end

    test "returns false when object doesn't exist" do
      key = "sessions/nonexistent/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 404, body: ""}}
      end)

      assert S3.exists?(key) == false
    end

    test "returns false on S3 errors" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 500, body: ""}}
      end)

      assert S3.exists?(key) == false
    end

    test "returns false on network errors" do
      key = "sessions/test123/file.txt"

      expect(Req, :request, fn _opts ->
        {:error, :timeout}
      end)

      assert S3.exists?(key) == false
    end
  end

  describe "list/1" do
    setup do
      setup_s3_config()
      :ok
    end

    test "successfully lists objects with prefix" do
      prefix = "sessions/test123/"

      xml_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>2</KeyCount>
        <MaxKeys>1000</MaxKeys>
        <IsTruncated>false</IsTruncated>
        <Contents>
          <Key>#{prefix}file1.txt</Key>
        </Contents>
        <Contents>
          <Key>#{prefix}file2.txt</Key>
        </Contents>
      </ListBucketResult>
      """

      expect(Req, :request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ "list-type=2"
        assert opts[:url] =~ "prefix=#{URI.encode_www_form(prefix)}"
        {:ok, %{status: 200, body: xml_response}}
      end)

      assert {:ok, keys} = S3.list(prefix)
      assert length(keys) == 2
      assert "#{prefix}file1.txt" in keys
      assert "#{prefix}file2.txt" in keys
    end

    test "handles empty list results" do
      prefix = "sessions/empty/"

      xml_response = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>0</KeyCount>
        <IsTruncated>false</IsTruncated>
      </ListBucketResult>
      """

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 200, body: xml_response}}
      end)

      assert {:ok, []} = S3.list(prefix)
    end

    test "handles paginated results" do
      prefix = "sessions/large/"

      xml_response_page1 = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>1</KeyCount>
        <IsTruncated>true</IsTruncated>
        <NextContinuationToken>token123</NextContinuationToken>
        <Contents>
          <Key>#{prefix}file1.txt</Key>
        </Contents>
      </ListBucketResult>
      """

      xml_response_page2 = """
      <?xml version="1.0" encoding="UTF-8"?>
      <ListBucketResult>
        <Name>test-bucket</Name>
        <Prefix>#{prefix}</Prefix>
        <KeyCount>1</KeyCount>
        <IsTruncated>false</IsTruncated>
        <Contents>
          <Key>#{prefix}file2.txt</Key>
        </Contents>
      </ListBucketResult>
      """

      Req
      |> expect(:request, fn opts ->
        refute opts[:url] =~ "continuation-token"
        {:ok, %{status: 200, body: xml_response_page1}}
      end)
      |> expect(:request, fn opts ->
        assert opts[:url] =~ "continuation-token=token123"
        {:ok, %{status: 200, body: xml_response_page2}}
      end)

      assert {:ok, keys} = S3.list(prefix)
      assert length(keys) == 2
      assert "#{prefix}file1.txt" in keys
      assert "#{prefix}file2.txt" in keys
    end

    test "returns error on S3 failure" do
      prefix = "sessions/test/"

      expect(Req, :request, fn _opts ->
        {:ok, %{status: 403, body: "Access Denied"}}
      end)

      assert {:error, {:s3_error, 403, "Access Denied"}} = S3.list(prefix)
    end
  end

  describe "configuration validation" do
    test "returns error when S3 bucket is not configured" do
      Application.put_env(:micelio, Micelio.Storage, [])

      assert {:error, :missing_s3_bucket} = S3.put("key", "content")
    end

    test "returns error when S3 credentials are not configured" do
      Application.put_env(:micelio, Micelio.Storage, s3_bucket: "test-bucket")

      assert {:error, :missing_s3_credentials} = S3.put("key", "content")
    end

    test "uses environment variables for configuration" do
      Application.put_env(:micelio, Micelio.Storage, [])

      System.put_env("S3_BUCKET", "env-bucket")
      System.put_env("AWS_ACCESS_KEY_ID", "env-key")
      System.put_env("AWS_SECRET_ACCESS_KEY", "env-secret")

      expect(Req, :request, fn opts ->
        assert opts[:url] =~ "env-bucket"
        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, _} = S3.put("key", "content")

      # Cleanup
      System.delete_env("S3_BUCKET")
      System.delete_env("AWS_ACCESS_KEY_ID")
      System.delete_env("AWS_SECRET_ACCESS_KEY")
    end

    test "prioritizes explicit config over environment variables" do
      Application.put_env(:micelio, Micelio.Storage,
        s3_bucket: "config-bucket",
        s3_access_key_id: "config-key",
        s3_secret_access_key: "config-secret"
      )

      System.put_env("S3_BUCKET", "env-bucket")

      expect(Req, :request, fn opts ->
        assert opts[:url] =~ "config-bucket"
        refute opts[:url] =~ "env-bucket"
        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, _} = S3.put("key", "content")

      System.delete_env("S3_BUCKET")
    end
  end

  describe "AWS Signature V4 authentication" do
    setup do
      setup_s3_config()
      :ok
    end

    test "includes required AWS authentication headers" do
      expect(Req, :request, fn opts ->
        headers = opts[:headers]
        header_names = Enum.map(headers, fn {name, _} -> String.downcase(name) end)

        assert "authorization" in header_names
        assert "x-amz-date" in header_names
        assert "x-amz-content-sha256" in header_names
        assert "host" in header_names

        # Verify authorization header format
        auth_header = get_header(headers, "authorization")
        assert auth_header =~ ~r/AWS4-HMAC-SHA256 Credential=/
        assert auth_header =~ ~r/SignedHeaders=/
        assert auth_header =~ ~r/Signature=/

        {:ok, %{status: 200, body: ""}}
      end)

      S3.put("test-key", "test-content")
    end

    test "includes content SHA256 for PUT requests" do
      content = "test content"
      expected_sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      expect(Req, :request, fn opts ->
        headers = opts[:headers]
        content_sha256 = get_header(headers, "x-amz-content-sha256")

        assert content_sha256 == expected_sha256
        {:ok, %{status: 200, body: ""}}
      end)

      S3.put("test-key", content)
    end

    test "uses empty string SHA256 for GET requests" do
      empty_sha256 = :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)

      expect(Req, :request, fn opts ->
        headers = opts[:headers]
        content_sha256 = get_header(headers, "x-amz-content-sha256")

        assert content_sha256 == empty_sha256
        {:ok, %{status: 200, body: "content"}}
      end)

      S3.get("test-key")
    end
  end

  describe "content-addressable storage integration" do
    setup do
      setup_s3_config()
      :ok
    end

    test "stores and retrieves content by hash-based keys" do
      content = "agent session data"
      # Simulate content-addressable key (SHA256 of content)
      content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      key = "artifacts/sha256:#{content_hash}"

      Req
      |> expect(:request, fn opts ->
        assert opts[:method] == :put
        assert opts[:url] =~ content_hash
        {:ok, %{status: 200, body: ""}}
      end)
      |> expect(:request, fn opts ->
        assert opts[:method] == :get
        assert opts[:url] =~ content_hash
        {:ok, %{status: 200, body: content}}
      end)

      assert {:ok, ^key} = S3.put(key, content)
      assert {:ok, ^content} = S3.get(key)
    end

    test "supports session-scoped artifact paths" do
      session_id = "abc123"
      artifact_key = "sessions/#{session_id}/artifacts/build.tar.gz"

      expect(Req, :request, fn opts ->
        assert opts[:url] =~ session_id
        assert opts[:url] =~ "artifacts"
        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, ^artifact_key} = S3.put(artifact_key, "build data")
    end
  end

  # Helper functions

  defp setup_s3_config do
    Application.put_env(:micelio, Micelio.Storage,
      backend: :s3,
      s3_bucket: "test-bucket",
      s3_region: "us-east-1",
      s3_access_key_id: "test-key-id",
      s3_secret_access_key: "test-secret-key",
      s3_endpoint: "https://s3.us-east-1.amazonaws.com"
    )
  end

  defp has_auth_headers?(headers) do
    header_names = Enum.map(headers, fn {name, _} -> String.downcase(name) end)

    "authorization" in header_names and
      "x-amz-date" in header_names and
      "x-amz-content-sha256" in header_names
  end

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == String.downcase(name) end)
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end
end
