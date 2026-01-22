defmodule MicelioWeb.Api.TokenContributionControllerTest do
  use MicelioWeb.ConnCase, async: false

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Projects

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("token-contrib-api@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{handle: "token-org", name: "Token Org"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "token-project",
        name: "Token Project",
        organization_id: organization.id
      })

    token = create_access_token(user)

    %{user: user, token: token, project: project, organization: organization}
  end

  test "creates token contribution and updates pool", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/token-contributions",
        %{
          token_contribution: %{amount: 50}
        }
      )

    body = json_response(conn, 201)
    assert body["data"]["contribution"]["amount"] == 50
    assert body["data"]["token_pool"]["balance"] == 50

    pool = AITokens.get_token_pool_by_project(project.id)
    assert pool.balance == 50
  end

  test "rejects invalid contribution amounts", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/token-contributions",
        %{
          token_contribution: %{amount: 0}
        }
      )

    body = json_response(conn, 422)
    assert "greater than 0" in body["error"]["amount"]
  end

  test "rejects missing token contribution payload", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/token-contributions",
        %{}
      )

    body = json_response(conn, 400)
    assert body["error"] == "token_contribution payload is required"
  end

  test "requires authentication", %{conn: conn, project: project, organization: organization} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/token-contributions",
        %{
          token_contribution: %{amount: 10}
        }
      )

    body = json_response(conn, 401)
    assert body["error"] == "Authentication required"
  end

  test "forbids contributions to private projects without access", %{
    conn: conn,
    organization: organization
  } do
    {:ok, private_project} =
      Projects.create_project(%{
        handle: "secret",
        name: "Secret",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, other_user} = Accounts.get_or_create_user_by_email("token-contrib-guest@example.com")
    other_token = create_access_token(other_user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{private_project.handle}/token-contributions",
        %{
          token_contribution: %{amount: 25}
        }
      )

    body = json_response(conn, 403)
    assert body["error"] == "Not authorized to contribute tokens"
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
