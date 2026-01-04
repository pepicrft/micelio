defmodule Micelio.Hif.SessionsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Hif.Session
  alias Micelio.Hif.Sessions

  describe "create_session/1" do
    test "creates a session with valid attributes" do
      project = insert_repository()
      user = insert_account()

      attrs = %{
        goal: "Add authentication to the API",
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, session} = Sessions.create_session(attrs)
      assert session.goal == "Add authentication to the API"
      assert session.state == "active"
      assert session.project_id == project.id
      assert session.user_id == user.id
      assert session.decisions == []
      assert session.conversation == []
      assert session.operations == []
    end

    test "returns error with missing goal" do
      project = insert_repository()
      user = insert_account()

      attrs = %{project_id: project.id, user_id: user.id}

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).goal
    end

    test "returns error with empty goal" do
      project = insert_repository()
      user = insert_account()

      attrs = %{goal: "", project_id: project.id, user_id: user.id}

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "can't be blank" in errors_on(changeset).goal
    end

    test "returns error with goal too long" do
      project = insert_repository()
      user = insert_account()

      attrs = %{
        goal: String.duplicate("a", 1001),
        project_id: project.id,
        user_id: user.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "should be at most 1000 character(s)" in errors_on(changeset).goal
    end

    test "returns error with invalid project_id" do
      user = insert_account()

      attrs = %{
        goal: "Test",
        project_id: Ecto.UUID.generate(),
        user_id: user.id
      }

      assert {:error, changeset} = Sessions.create_session(attrs)
      assert "does not exist" in errors_on(changeset).project_id
    end
  end

  describe "get_session/1" do
    test "returns the session with the given id" do
      session = insert_session()

      assert found = Sessions.get_session(session.id)
      assert found.id == session.id
      assert found.goal == session.goal
    end

    test "returns nil for non-existent id" do
      assert Sessions.get_session(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_active_session/2" do
    test "returns active session for user in project" do
      project = insert_repository()
      user = insert_account()
      session = insert_session(project: project, user: user, state: "active")

      assert found = Sessions.get_active_session(project.id, user.id)
      assert found.id == session.id
    end

    test "returns nil when no active session exists" do
      project = insert_repository()
      user = insert_account()
      _landed = insert_session(project: project, user: user, state: "landed")

      assert Sessions.get_active_session(project.id, user.id) == nil
    end

    test "returns nil for different user" do
      project = insert_repository()
      user1 = insert_account()
      user2 = insert_account()
      _session = insert_session(project: project, user: user1, state: "active")

      assert Sessions.get_active_session(project.id, user2.id) == nil
    end
  end

  describe "list_sessions/2" do
    test "lists all sessions for a project" do
      project = insert_repository()
      session1 = insert_session(project: project)
      session2 = insert_session(project: project)
      _other = insert_session()

      sessions = Sessions.list_sessions(project.id)

      assert length(sessions) == 2
      ids = Enum.map(sessions, & &1.id)
      assert session1.id in ids
      assert session2.id in ids
    end

    test "filters by state" do
      project = insert_repository()
      active = insert_session(project: project, state: "active")
      _landed = insert_session(project: project, state: "landed")

      sessions = Sessions.list_sessions(project.id, state: "active")

      assert length(sessions) == 1
      assert hd(sessions).id == active.id
    end

    test "filters by user" do
      project = insert_repository()
      user = insert_account()
      session = insert_session(project: project, user: user)
      _other = insert_session(project: project)

      sessions = Sessions.list_sessions(project.id, user_id: user.id)

      assert length(sessions) == 1
      assert hd(sessions).id == session.id
    end

    test "respects limit" do
      project = insert_repository()
      for _ <- 1..5, do: insert_session(project: project)

      sessions = Sessions.list_sessions(project.id, limit: 3)

      assert length(sessions) == 3
    end
  end

  describe "record_decision/2" do
    test "adds decision to active session" do
      session = insert_session(state: "active")

      assert {:ok, updated} =
               Sessions.record_decision(session, "Using JWT because user specified")

      assert length(updated.decisions) == 1
      [decision] = updated.decisions
      assert decision["text"] == "Using JWT because user specified"
      assert decision["recorded_at"]
    end

    test "appends to existing decisions" do
      session = insert_session(state: "active", decisions: [%{"text" => "First"}])

      assert {:ok, updated} = Sessions.record_decision(session, "Second")

      assert length(updated.decisions) == 2
    end

    test "returns error for landed session" do
      session = insert_session(state: "landed")

      assert {:error, {:invalid_state, _}} = Sessions.record_decision(session, "Test")
    end
  end

  describe "record_message/3" do
    test "adds message to active session" do
      session = insert_session(state: "active")

      assert {:ok, updated} = Sessions.record_message(session, "human", "Should we use JWT?")

      assert length(updated.conversation) == 1
      [message] = updated.conversation
      assert message["role"] == "human"
      assert message["content"] == "Should we use JWT?"
      assert message["recorded_at"]
    end

    test "supports agent and system roles" do
      session = insert_session(state: "active")

      assert {:ok, s1} = Sessions.record_message(session, "agent", "I recommend JWT")
      assert {:ok, s2} = Sessions.record_message(s1, "system", "Session started")

      assert length(s2.conversation) == 2
    end

    test "returns error for landed session" do
      session = insert_session(state: "landed")

      assert {:error, {:invalid_state, _}} = Sessions.record_message(session, "human", "Test")
    end
  end

  describe "record_operation/4" do
    test "adds write operation" do
      session = insert_session(state: "active")

      assert {:ok, updated} =
               Sessions.record_operation(session, "write", "src/auth.ex", %{"hash" => "abc123"})

      assert length(updated.operations) == 1
      [op] = updated.operations
      assert op["type"] == "write"
      assert op["path"] == "src/auth.ex"
      assert op["hash"] == "abc123"
    end

    test "supports delete, rename, mkdir operations" do
      session = insert_session(state: "active")

      assert {:ok, s1} = Sessions.record_operation(session, "delete", "old.ex")
      assert {:ok, s2} = Sessions.record_operation(s1, "rename", "new.ex", %{"from" => "old.ex"})
      assert {:ok, s3} = Sessions.record_operation(s2, "mkdir", "lib/auth")

      assert length(s3.operations) == 3
    end

    test "returns error for abandoned session" do
      session = insert_session(state: "abandoned")

      assert {:error, {:invalid_state, _}} =
               Sessions.record_operation(session, "write", "test.ex")
    end
  end

  describe "land_session/1" do
    test "transitions active session to landed" do
      session = insert_session(state: "active")

      assert {:ok, landed} = Sessions.land_session(session)

      assert landed.state == "landed"
      assert landed.landed_at != nil
    end

    test "returns error for already landed session" do
      session = insert_session(state: "landed")

      assert {:error, {:invalid_state, _}} = Sessions.land_session(session)
    end

    test "returns error for abandoned session" do
      session = insert_session(state: "abandoned")

      assert {:error, {:invalid_state, _}} = Sessions.land_session(session)
    end
  end

  describe "abandon_session/1" do
    test "transitions active session to abandoned" do
      session = insert_session(state: "active")

      assert {:ok, abandoned} = Sessions.abandon_session(session)

      assert abandoned.state == "abandoned"
    end

    test "can abandon conflicted session" do
      session = insert_session(state: "conflicted")

      assert {:ok, abandoned} = Sessions.abandon_session(session)

      assert abandoned.state == "abandoned"
    end

    test "returns error for landed session" do
      session = insert_session(state: "landed")

      assert {:error, {:invalid_state, _}} = Sessions.abandon_session(session)
    end
  end

  # Test helpers - insert functions create isolated test data

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
    decisions = Keyword.get(attrs, :decisions, [])
    conversation = Keyword.get(attrs, :conversation, [])
    operations = Keyword.get(attrs, :operations, [])

    {:ok, session} =
      %Session{}
      |> Ecto.Changeset.change(%{
        goal: "Test session #{System.unique_integer([:positive])}",
        state: state,
        project_id: project.id,
        user_id: user.id,
        decisions: decisions,
        conversation: conversation,
        operations: operations
      })
      |> Micelio.Repo.insert()

    session
  end
end
