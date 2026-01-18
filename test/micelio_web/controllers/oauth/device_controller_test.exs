defmodule MicelioWeb.Oauth.DeviceControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.OAuth

  test "uses existing client when credentials are provided", %{conn: conn} do
    {:ok, client} = OAuth.register_device_client(%{"name" => "hif"})

    payload = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "device_name" => "hif"
    }

    conn = post(conn, "/auth/device", payload)
    assert %{"device_code" => device_code} = json_response(conn, 200)

    grant = OAuth.get_device_grant_by_device_code(device_code)
    assert grant.client_id == client.client_id
  end

  test "rejects invalid client credentials", %{conn: conn} do
    {:ok, client} = OAuth.register_device_client(%{"name" => "hif"})

    payload = %{
      "client_id" => client.client_id,
      "client_secret" => "bad-secret",
      "device_name" => "hif"
    }

    conn = post(conn, "/auth/device", payload)
    assert %{"code" => "invalid_client"} = json_response(conn, 400)
  end
end
