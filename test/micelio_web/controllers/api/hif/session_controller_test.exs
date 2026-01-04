defmodule MicelioWeb.API.Hif.SessionControllerTest do
  use MicelioWeb.ConnCase, async: true

  describe "POST /api/hif/sessions" do
    test "creates session with valid params", %{conn: conn} do
      project = insert_repository()
      user = insert_account()

      params = %{
        "goal" => "Add authentication",
        "project_id" => project.id,
        "user_id" => user.id
      }

      conn = post(conn, ~p"/api/hif/sessions", params)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["goal"] == "Add authentication"
      assert data["state"] == "active"
      assert data["project_id"] == project.id
      assert data["user_id"] == user.id
    end

    test "returns error with missing goal", %{conn: conn} do
      project = insert_repository()
      user = insert_account()

      params = %{"project_id" => project.id, "user_id" => user.id}

      conn = post(conn, ~p"/api/hif/sessions", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["goal"] != nil
    end
  end

  describe "GET /api/hif/sessions/:id" do
    test "returns session by id", %{conn: conn} do
      session = insert_session()

      conn = get(conn, ~p"/api/hif/sessions/#{session.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == session.id
      assert data["goal"] == session.goal
    end

    test "returns 404 for non-existent session", %{conn: conn} do
      conn = get(conn, ~p"/api/hif/sessions/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end
  end

  describe "GET /api/hif/sessions" do
    test "lists sessions for project", %{conn: conn} do
      project = insert_repository()
      session1 = insert_session(project: project)
      session2 = insert_session(project: project)
      _other = insert_session()

      conn = get(conn, ~p"/api/hif/sessions", %{"project_id" => project.id})

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 2
      ids = Enum.map(data, & &1["id"])
      assert session1.id in ids
      assert session2.id in ids
    end

    test "filters by state", %{conn: conn} do
      project = insert_repository()
      active = insert_session(project: project, state: "active")
      _landed = insert_session(project: project, state: "landed")

      conn = get(conn, ~p"/api/hif/sessions", %{"project_id" => project.id, "state" => "active"})

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data) == 1
      assert hd(data)["id"] == active.id
    end

    test "returns error without project_id", %{conn: conn} do
      conn = get(conn, ~p"/api/hif/sessions")

      assert json_response(conn, 400)
    end
  end

  describe "POST /api/hif/sessions/:id/decisions" do
    test "adds decision to session", %{conn: conn} do
      session = insert_session(state: "active")

      params = %{"text" => "Using JWT for stateless auth"}

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/decisions", params)

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data["decisions"]) == 1
      assert hd(data["decisions"])["text"] == "Using JWT for stateless auth"
    end

    test "returns 404 for non-existent session", %{conn: conn} do
      params = %{"text" => "Test"}

      conn = post(conn, ~p"/api/hif/sessions/#{Ecto.UUID.generate()}/decisions", params)

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/hif/sessions/:id/messages" do
    test "adds message to session", %{conn: conn} do
      session = insert_session(state: "active")

      params = %{"role" => "human", "content" => "Should we use JWT?"}

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/messages", params)

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data["conversation"]) == 1
      [message] = data["conversation"]
      assert message["role"] == "human"
      assert message["content"] == "Should we use JWT?"
    end
  end

  describe "POST /api/hif/sessions/:id/operations" do
    test "adds operation to session", %{conn: conn} do
      session = insert_session(state: "active")

      params = %{"type" => "write", "path" => "lib/auth.ex", "hash" => "abc123"}

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/operations", params)

      assert %{"data" => data} = json_response(conn, 200)
      assert length(data["operations"]) == 1
      [op] = data["operations"]
      assert op["type"] == "write"
      assert op["path"] == "lib/auth.ex"
      assert op["hash"] == "abc123"
    end
  end

  describe "POST /api/hif/sessions/:id/land" do
    test "lands active session", %{conn: conn} do
      session = insert_session(state: "active")

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/land")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "landed"
      assert data["landed_at"] != nil
    end

    test "returns error for already landed session", %{conn: conn} do
      session = insert_session(state: "landed")

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/land")

      assert json_response(conn, 422)
    end
  end

  describe "POST /api/hif/sessions/:id/abandon" do
    test "abandons active session", %{conn: conn} do
      session = insert_session(state: "active")

      conn = post(conn, ~p"/api/hif/sessions/#{session.id}/abandon")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["state"] == "abandoned"
    end
  end

  # Test helpers - isolated data per test

  defp insert_account(attrs \\ %{}) do
    {:ok, account} =
      %Micelio.Accounts.Account{}
      |> Micelio.Accounts.Account.changeset(
        Map.merge(
          %{
            handle: "user_#{System.unique_integer([:positive])}",
            email: "user_#{System.unique_integer([:positive])}@example.com"
          },
          attrs
        )
      )
      |> Micelio.Repo.insert()

    account
  end

  defp insert_repository(attrs \\ %{}) do
    account = Map.get_lazy(attrs, :account, fn -> insert_account() end)

    {:ok, repo} =
      %Micelio.Repositories.Repository{}
      |> Micelio.Repositories.Repository.changeset(
        Map.merge(
          %{
            handle: "repo_#{System.unique_integer([:positive])}",
            account_id: account.id
          },
          Map.delete(attrs, :account)
        )
      )
      |> Micelio.Repo.insert()

    repo
  end

  defp insert_session(attrs \\ []) do
    project = Keyword.get_lazy(attrs, :project, fn -> insert_repository() end)
    user = Keyword.get_lazy(attrs, :user, fn -> insert_account() end)
    state = Keyword.get(attrs, :state, "active")

    {:ok, session} =
      %Micelio.Hif.Session{}
      |> Ecto.Changeset.change(%{
        goal: "Test session #{System.unique_integer([:positive])}",
        state: state,
        project_id: project.id,
        user_id: user.id,
        decisions: [],
        conversation: [],
        operations: []
      })
      |> Micelio.Repo.insert()

    session
  end
end
