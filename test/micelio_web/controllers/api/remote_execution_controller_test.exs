defmodule MicelioWeb.Api.RemoteExecutionControllerTest do
  use MicelioWeb.ConnCase, async: false

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients

  setup do
    original = Application.get_env(:micelio, :remote_execution, [])
    Application.put_env(:micelio, :remote_execution, allowed_commands: ["echo"])

    on_exit(fn ->
      Application.put_env(:micelio, :remote_execution, original)
    end)

    {:ok, user} = Accounts.get_or_create_user_by_email("remote-exec-api@example.com")
    token = create_access_token(user)

    %{user: user, token: token}
  end

  test "creates and shows a remote execution task", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/api/remote-executions", %{command: "echo", args: ["hello"]})

    body = json_response(conn, 201)
    task_id = body["data"]["id"]

    assert body["data"]["command"] == "echo"
    assert body["data"]["args"] == ["hello"]
    assert body["data"]["status"] in ["queued", "running", "succeeded", "failed"]

    conn =
      conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/remote-executions/#{task_id}")

    show_body = json_response(conn, 200)
    assert show_body["data"]["id"] == task_id
  end

  test "requires authentication", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/remote-executions", %{command: "echo", args: ["hello"]})

    body = json_response(conn, 401)
    assert body["error"] == "Authentication required"
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "mic"})
    client = Clients.get_client(device_client.client_id)

    params = %{
      client: client,
      scope: "",
      sub: to_string(user.id),
      resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
    }

    {:ok, token} = AccessTokens.create(params, refresh_token: true)
    Map.get(token, :value) || Map.get(token, :access_token)
  end
end
