defmodule Micelio.Storage.UserS3ConfigTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Storage

  defmodule SuccessValidator do
    def validate(_config), do: {:ok, %{ok?: true, errors: []}}
  end

  defmodule FailureValidator do
    def validate(_config), do: {:error, %{ok?: false, errors: ["boom"]}}
  end

  setup do
    previous = Application.get_env(:micelio, Storage)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Storage)
        _ -> Application.put_env(:micelio, Storage, previous)
      end
    end)

    :ok
  end

  test "upserts and validates S3 config" do
    Application.put_env(:micelio, Storage, s3_validator: SuccessValidator)
    user = user_fixture()

    attrs = %{
      provider: "aws_s3",
      bucket_name: "micelio-bucket",
      region: "us-east-1",
      endpoint_url: "",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      path_prefix: "sessions/"
    }

    assert {:ok, config, {:ok, _result}} = Storage.upsert_user_s3_config(user, attrs)
    assert config.validated_at
    assert config.last_error == nil
  end

  test "keeps existing credentials when blank" do
    Application.put_env(:micelio, Storage, s3_validator: SuccessValidator)
    user = user_fixture()

    attrs = %{
      provider: "aws_s3",
      bucket_name: "micelio-bucket",
      region: "us-east-1",
      endpoint_url: "",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      path_prefix: "sessions/"
    }

    assert {:ok, _config, {:ok, _result}} = Storage.upsert_user_s3_config(user, attrs)

    update_attrs = %{
      provider: "aws_s3",
      bucket_name: "updated-bucket",
      region: "us-east-1",
      endpoint_url: "",
      access_key_id: "",
      secret_access_key: "",
      path_prefix: "sessions/"
    }

    assert {:ok, updated, {:ok, _result}} = Storage.upsert_user_s3_config(user, update_attrs)
    assert updated.bucket_name == "updated-bucket"
    assert updated.access_key_id == "access-key"
    assert updated.secret_access_key == "secret-key"
  end

  test "records validation errors on failure" do
    Application.put_env(:micelio, Storage, s3_validator: FailureValidator)
    user = user_fixture()

    attrs = %{
      provider: "aws_s3",
      bucket_name: "micelio-bucket",
      region: "us-east-1",
      endpoint_url: "",
      access_key_id: "access-key",
      secret_access_key: "secret-key",
      path_prefix: "sessions/"
    }

    assert {:ok, config, {:error, _result}} = Storage.upsert_user_s3_config(user, attrs)
    assert config.validated_at == nil
    assert config.last_error =~ "boom"
  end

  defp user_fixture do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email())
    user
  end

  defp unique_email do
    "s3-config-#{System.unique_integer([:positive])}@example.com"
  end
end
