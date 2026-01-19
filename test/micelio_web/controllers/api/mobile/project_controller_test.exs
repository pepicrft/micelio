defmodule MicelioWeb.Api.Mobile.ProjectControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Projects

  setup do
    {:ok, user} =
      Accounts.get_or_create_user_by_email("mobile-projects-#{unique_suffix()}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "mobile-org-#{unique_suffix()}",
        name: "Mobile Org"
      })

    {:ok, public_project} =
      Projects.create_project(
        %{
          handle: "public",
          name: "Public Project",
          organization_id: organization.id,
          visibility: "public"
        },
        user: user
      )

    {:ok, private_project} =
      Projects.create_project(
        %{
          handle: "private",
          name: "Private Project",
          organization_id: organization.id,
          visibility: "private"
        },
        user: user
      )

    %{
      user: user,
      organization: organization,
      public_project: public_project,
      private_project: private_project
    }
  end

  test "lists public projects for anonymous users", %{conn: conn, public_project: public_project} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/mobile/projects")

    body = json_response(conn, 200)

    assert Enum.any?(body["data"], fn project -> project["id"] == public_project.id end)
    assert Enum.all?(body["data"], fn project -> project["visibility"] == "public" end)
  end

  test "lists private projects for authenticated users", %{
    conn: conn,
    user: user,
    private_project: private_project
  } do
    access_token = create_access_token(user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> get(~p"/api/mobile/projects")

    body = json_response(conn, 200)

    assert Enum.any?(body["data"], fn project -> project["id"] == private_project.id end)
  end

  test "paginates project results", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/mobile/projects?limit=1")

    body = json_response(conn, 200)

    assert body["pagination"]["limit"] == 1
    assert body["pagination"]["offset"] == 0
  end

  test "shows public project details", %{
    conn: conn,
    organization: organization,
    public_project: project
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/mobile/projects/#{organization.account.handle}/#{project.handle}")

    body = json_response(conn, 200)

    assert body["data"]["id"] == project.id
    assert body["data"]["organization"]["handle"] == organization.account.handle
  end

  test "blocks private projects for anonymous users", %{
    conn: conn,
    organization: organization,
    private_project: project
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/mobile/projects/#{organization.account.handle}/#{project.handle}")

    body = json_response(conn, 403)

    assert body["error"] == "Project is private"
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

  defp unique_suffix do
    System.unique_integer([:positive])
  end
end
