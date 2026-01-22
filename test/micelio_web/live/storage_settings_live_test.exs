defmodule MicelioWeb.StorageSettingsLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Storage

  defmodule SuccessValidator do
    def validate(_config) do
      {:ok,
       %{
         ok?: true,
         errors: [],
         warnings: [],
         steps: %{endpoint: :ok, bucket: :ok, write: :ok, read: :ok, delete: :ok}
       }}
    end
  end

  defmodule ErrorValidator do
    def validate(_config) do
      {:error,
       %{
         ok?: false,
         errors: ["Access denied."],
         warnings: [],
         steps: %{endpoint: {:error, "Access denied."}}
       }}
    end
  end

  setup :use_success_validator

  defp use_success_validator(_) do
    previous = Application.get_env(:micelio, Storage)

    Application.put_env(:micelio, Storage, s3_validator: SuccessValidator)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Storage)
        _ -> Application.put_env(:micelio, Storage, previous)
      end
    end)

    :ok
  end

  test "requires authentication", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/auth/login"}}} = live(conn, ~p"/settings/storage")
  end

  test "saves storage settings", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-settings@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key",
      "path_prefix" => "sessions/"
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_submit()

    config = Storage.get_user_s3_config(user)
    assert config.bucket_name == "user-bucket"
    assert config.provider == :aws_s3
    assert config.validated_at
  end

  test "tests connection without saving", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-test@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key",
      "path_prefix" => ""
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_change()

    view
    |> element("#storage-test-connection")
    |> render_click()

    assert render(view) =~ "Connection successful"
    assert Storage.get_user_s3_config(user) == nil
  end

  test "toggles secret access key visibility", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-toggle@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    assert has_element?(view, ~s(input[name="s3_config[secret_access_key]"][type="password"]))

    view
    |> element("#storage-secret-toggle")
    |> render_click()

    assert has_element?(view, ~s(input[name="s3_config[secret_access_key]"][type="text"]))

    view
    |> element("#storage-secret-toggle")
    |> render_click()

    assert has_element?(view, ~s(input[name="s3_config[secret_access_key]"][type="password"]))
  end

  test "shows validation errors when test connection fails", %{conn: conn} do
    previous = Application.get_env(:micelio, Storage)
    Application.put_env(:micelio, Storage, s3_validator: ErrorValidator)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Storage)
        _ -> Application.put_env(:micelio, Storage, previous)
      end
    end)

    {:ok, user} = Accounts.get_or_create_user_by_email("storage-test-error@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key",
      "path_prefix" => ""
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_change()

    view
    |> element("#storage-test-connection")
    |> render_click()

    assert render(view) =~ "Connection failed."
    assert render(view) =~ "Access denied."
    assert Storage.get_user_s3_config(user) == nil
  end

  test "defaults region and endpoint when provider changes", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-defaults@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "",
      "endpoint_url" => "",
      "access_key_id" => "",
      "secret_access_key" => "",
      "path_prefix" => ""
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_change()

    assert has_element?(
             view,
             ~s(select[name="s3_config[region]"] option[selected][value="us-east-1"])
           )

    assert has_element?(
             view,
             ~s(input[name="s3_config[endpoint_url]"][value="https://s3.us-east-1.amazonaws.com"])
           )
  end

  test "defaults endpoint for regionless providers", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-defaults-r2@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "cloudflare_r2",
      "bucket_name" => "user-bucket",
      "region" => "",
      "endpoint_url" => "",
      "access_key_id" => "",
      "secret_access_key" => "",
      "path_prefix" => ""
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_change()

    assert has_element?(
             view,
             ~s(input[name="s3_config[endpoint_url]"][value="https://account-id.r2.cloudflarestorage.com"])
           )
  end

  test "hides region field for regionless providers", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-regionless@example.com")
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    params = %{
      "provider" => "cloudflare_r2",
      "bucket_name" => "user-bucket",
      "region" => "",
      "endpoint_url" => "",
      "access_key_id" => "",
      "secret_access_key" => "",
      "path_prefix" => ""
    }

    view
    |> form("#storage-settings-form", s3_config: params)
    |> render_change()

    refute has_element?(view, "select[name=\"s3_config[region]\"]")

    assert has_element?(
             view,
             "input[name=\"s3_config[endpoint_url]\"]"
           )
  end

  test "removes stored configuration", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-remove@example.com")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "remove-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key"
    }

    {:ok, _config, _result} = Storage.upsert_user_s3_config(user, params)

    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    view
    |> element("#storage-remove-configuration")
    |> render_click()

    assert Storage.get_user_s3_config(user) == nil
  end

  test "shows saved validation error status", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("storage-invalid@example.com")

    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "invalid-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key"
    }

    {:ok, _config, _result} =
      Storage.upsert_user_s3_config(user, params, validator: ErrorValidator)

    conn = log_in_user(conn, user)
    {:ok, _view, html} = live(conn, ~p"/settings/storage")

    assert html =~ "Saved config failed validation."
    assert html =~ "Access denied."
  end
end
