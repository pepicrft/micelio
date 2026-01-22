defmodule Micelio.Storage.UserS3Test do
  use Micelio.DataCase, async: true

  import Mimic

  alias Micelio.Accounts
  alias Micelio.Repo
  alias Micelio.Storage
  alias Micelio.Storage.{S3Config, UserS3}
  alias Micelio.StorageHelper

  setup :verify_on_exit!
  setup :set_mimic_private

  setup do
    Mimic.copy(Req)
    :ok
  end

  test "uses user S3 config when validated" do
    user = user_fixture()

    config =
      s3_config_fixture(user, %{validated_at: DateTime.utc_now(), path_prefix: "users/#{user.id}"})

    key = "projects/1/file.txt"
    content = "user-s3"

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      assert String.contains?(opts[:url], "#{config.bucket_name}.")
      assert String.ends_with?(opts[:url], "/users/#{user.id}/projects/1/file.txt")
      {:ok, %{status: 200, body: ""}}
    end)

    assert {:ok, ^key} = UserS3.put(user.id, key, content)
  end

  test "falls back to instance storage when no config exists" do
    user = user_fixture()
    {:ok, storage} = StorageHelper.create_isolated_storage()

    on_exit(fn ->
      StorageHelper.cleanup(storage)
    end)

    StorageHelper.with_config(storage, fn ->
      key = "projects/2/file.txt"
      content = "fallback"

      assert {:ok, ^key} = UserS3.put(user.id, key, content)
      assert {:ok, ^content} = Storage.get(key)
    end)
  end

  test "marks config invalid after repeated failures and falls back" do
    user = user_fixture()
    config = s3_config_fixture(user, %{validated_at: DateTime.utc_now()})
    {:ok, storage} = StorageHelper.create_isolated_storage()

    previous = Application.get_env(:micelio, UserS3)
    Application.put_env(:micelio, UserS3, failure_threshold: 1)

    on_exit(fn ->
      StorageHelper.cleanup(storage)

      case previous do
        nil -> Application.delete_env(:micelio, UserS3)
        _ -> Application.put_env(:micelio, UserS3, previous)
      end
    end)

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      {:ok, %{status: 500, body: "boom"}}
    end)

    StorageHelper.with_config(storage, fn ->
      key = "projects/3/file.txt"
      content = "fallback-on-error"

      assert {:ok, ^key} = UserS3.put(user.id, key, content)
      assert {:ok, ^content} = Storage.get(key)
    end)

    updated = Repo.get!(S3Config, config.id)
    assert updated.validated_at == nil
    assert updated.last_error =~ "S3 error 500"
  end

  test "emits telemetry for user backend success" do
    user = user_fixture()
    user_id = user.id
    _config = s3_config_fixture(user, %{validated_at: DateTime.utc_now()})
    key = "projects/4/file.txt"
    content = "telemetry"

    attach_storage_telemetry()

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      {:ok, %{status: 200, body: ""}}
    end)

    assert {:ok, ^key} = UserS3.put(user.id, key, content)

    assert_receive {:telemetry,
                    %{
                      backend: :user_s3,
                      fallback: false,
                      operation: :put,
                      status: :ok,
                      user_id: ^user_id
                    }}
  end

  test "emits telemetry for fallback to instance storage" do
    user = user_fixture()
    user_id = user.id
    _config = s3_config_fixture(user, %{validated_at: DateTime.utc_now()})
    {:ok, storage} = StorageHelper.create_isolated_storage()

    on_exit(fn ->
      StorageHelper.cleanup(storage)
    end)

    attach_storage_telemetry()

    expect(Req, :request, fn opts ->
      assert opts[:method] == :put
      {:ok, %{status: 500, body: "boom"}}
    end)

    StorageHelper.with_config(storage, fn ->
      key = "projects/5/file.txt"
      content = "fallback-telemetry"

      assert {:ok, ^key} = UserS3.put(user.id, key, content)
      assert {:ok, ^content} = Storage.get(key)
    end)

    assert_receive {:telemetry,
                    %{
                      backend: :user_s3,
                      fallback: false,
                      operation: :put,
                      status: :error,
                      user_id: ^user_id
                    }}

    assert_receive {:telemetry,
                    %{
                      backend: :instance,
                      fallback: true,
                      operation: :put,
                      status: :ok,
                      user_id: ^user_id
                    }}
  end

  defp user_fixture do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email())
    user
  end

  defp unique_email do
    "user-s3-#{System.unique_integer([:positive])}@example.com"
  end

  defp s3_config_fixture(user, overrides \\ %{}) do
    attrs =
      %{
        user_id: user.id,
        provider: :aws_s3,
        bucket_name: "user-bucket",
        region: "us-east-1",
        endpoint_url: "https://s3.us-east-1.amazonaws.com",
        access_key_id: "access-key",
        secret_access_key: "secret-key",
        path_prefix: nil,
        validated_at: nil,
        last_error: nil
      }
      |> Map.merge(overrides)

    Repo.insert!(S3Config.changeset(%S3Config{}, attrs))
  end

  defp attach_storage_telemetry do
    id = "user-s3-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      id,
      [:micelio, :storage, :operation],
      fn _event, _measurements, metadata, pid ->
        send(pid, {:telemetry, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(id)
    end)

    :ok
  end
end
