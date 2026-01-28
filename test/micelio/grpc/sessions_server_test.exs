defmodule Micelio.GRPC.SessionsServerTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use Micelio.DataCase, async: false

  import Mimic

  alias Micelio.Accounts
  alias Micelio.GRPC.Sessions.V1.CaptureSessionEventRequest
  alias Micelio.GRPC.Sessions.V1.CaptureSessionEventResponse
  alias Micelio.GRPC.Sessions.V1.FileChange
  alias Micelio.GRPC.Sessions.V1.LandSessionRequest
  alias Micelio.GRPC.Sessions.V1.SessionResponse
  alias Micelio.GRPC.Sessions.V1.SessionService.Server, as: SessionsServer
  alias Micelio.Mic.Landing
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Storage
  alias Micelio.StorageHelper
  alias Micelio.Webhooks

  setup :verify_on_exit!
  setup :set_mimic_global
  setup :setup_storage

  test "land_session dispatches webhooks for landing and push events" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-land@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-org",
        name: "GRPC Sessions Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-repo",
        name: "GRPC Session Repo",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-1",
        goal: "Ship webhooks",
        project_id: project.id,
        user_id: user.id
      })

    landing_time = DateTime.utc_now() |> DateTime.truncate(:second)

    expect(Landing, :land_session, fn %Sessions.Session{} = landed_session ->
      assert landed_session.id == session.id
      {:ok, %{position: 12, landed_at: landing_time}}
    end)

    expect(Webhooks, :dispatch_session_landed, fn dispatched_project,
                                                  dispatched_session,
                                                  position ->
      assert dispatched_project.id == project.id
      assert dispatched_session.status == "landed"
      assert dispatched_session.metadata["landing_position"] == 12
      assert position == 12
      send(self(), :webhooks_dispatched)
      :ok
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: []
        },
        nil
      )

    assert %SessionResponse{} = response
    assert response.session.session_id == session.session_id
    assert response.session.status == "landed"
    assert response.session.landing_position == 12
    assert_receive :webhooks_dispatched
  end

  test "land_session blocks direct lands to protected main" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-protected@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-protected-org",
        name: "GRPC Sessions Protected Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-protected-repo",
        name: "GRPC Session Protected Repo",
        organization_id: organization.id,
        protect_main_branch: true
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-protected-1",
        goal: "Protect main",
        project_id: project.id,
        user_id: user.id
      })

    Mimic.stub(Landing, :land_session, fn _session ->
      flunk("Landing should not be invoked for protected main branch")
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: []
        },
        nil
      )

    assert {:error, %GRPC.RPCError{message: message}} = response
    assert message =~ "Direct lands to main are blocked"
  end

  test "land_session blocks when secret scanning detects credentials" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-secret@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-secret-org",
        name: "GRPC Sessions Secret Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-secret-repo",
        name: "GRPC Session Secret Repo",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-secret-1",
        goal: "Avoid secrets",
        project_id: project.id,
        user_id: user.id
      })

    Mimic.stub(Landing, :land_session, fn _session ->
      flunk("Landing should not be invoked when secrets are detected")
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: [
            %FileChange{
              path: "lib/secrets.ex",
              content: "token = \"ghp_abcdefghijklmnopqrstuvwxyz0123456789\"\n",
              change_type: "added"
            }
          ]
        },
        nil
      )

    assert {:error, %GRPC.RPCError{message: message}} = response
    assert message =~ "Potential secrets detected"

    persisted = Sessions.get_session_by_session_id(session.session_id)
    assert persisted.status == "active"
  end

  test "land_session blocks protected main when target branch uses refs prefix" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-protected-ref@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-protected-ref-org",
        name: "GRPC Sessions Protected Ref Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-protected-ref-repo",
        name: "GRPC Session Protected Ref Repo",
        organization_id: organization.id,
        protect_main_branch: true
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-protected-ref-1",
        goal: "Protect main via refs",
        project_id: project.id,
        user_id: user.id,
        metadata: %{"target_branch" => "refs/heads/main"}
      })

    Mimic.stub(Landing, :land_session, fn _session ->
      flunk("Landing should not be invoked for protected main branch")
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: []
        },
        nil
      )

    assert {:error, %GRPC.RPCError{message: message}} = response
    assert message =~ "Direct lands to main are blocked"
  end

  test "land_session allows protected projects when target branch is non-main" do
    {:ok, user} =
      Accounts.get_or_create_user_by_email("grpc-session-protected-feature@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-protected-feature-org",
        name: "GRPC Sessions Protected Feature Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-protected-feature-repo",
        name: "GRPC Session Protected Feature Repo",
        organization_id: organization.id,
        protect_main_branch: true
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-protected-feature-1",
        goal: "Protect main via feature branch",
        project_id: project.id,
        user_id: user.id
      })

    landing_time = DateTime.utc_now() |> DateTime.truncate(:second)

    expect(Landing, :land_session, fn %Sessions.Session{} = landed_session ->
      assert landed_session.metadata["target_branch"] == "feature/branch"
      {:ok, %{position: 3, landed_at: landing_time}}
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: [],
          target_branch: "feature/branch"
        },
        nil
      )

    assert %SessionResponse{} = response
    assert response.session.session_id == session.session_id
    assert response.session.status == "landed"
    assert response.session.landing_position == 3
  end

  test "land_session allows target branch override when main is protected" do
    {:ok, user} =
      Accounts.get_or_create_user_by_email("grpc-session-protected-override@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-protected-override-org",
        name: "GRPC Sessions Protected Override Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-protected-override-repo",
        name: "GRPC Session Protected Override Repo",
        organization_id: organization.id,
        protect_main_branch: true
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-protected-override-1",
        goal: "Protect main via target override",
        project_id: project.id,
        user_id: user.id
      })

    landing_time = DateTime.utc_now() |> DateTime.truncate(:second)

    Mimic.stub(Landing, :land_session, fn %Sessions.Session{} = landed_session ->
      assert landed_session.id == session.id
      {:ok, %{position: 9, landed_at: landing_time}}
    end)

    Mimic.stub(Webhooks, :dispatch_session_landed, fn _project, _session, _position ->
      :ok
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: [],
          target_branch: "feature/flag"
        },
        nil
      )

    assert %SessionResponse{} = response
    assert response.session.status == "landed"

    updated_session = Sessions.get_session_by_session_id(session.session_id)
    assert updated_session.metadata["target_branch"] == "feature/flag"
  end

  test "land_session blocks protected main when target branch uses refs remotes prefix" do
    {:ok, user} =
      Accounts.get_or_create_user_by_email("grpc-session-protected-remotes@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-protected-remotes-org",
        name: "GRPC Sessions Protected Remotes Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-protected-remotes-repo",
        name: "GRPC Session Protected Remotes Repo",
        organization_id: organization.id,
        protect_main_branch: true
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-protected-remotes-1",
        goal: "Protect main via refs remotes",
        project_id: project.id,
        user_id: user.id,
        metadata: %{"branch" => "refs/remotes/origin/main"}
      })

    Mimic.stub(Landing, :land_session, fn _session ->
      flunk("Landing should not be invoked for protected main branch")
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: []
        },
        nil
      )

    assert {:error, %GRPC.RPCError{message: message}} = response
    assert message =~ "Direct lands to main are blocked"
  end

  test "capture_session_event stores output payloads" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-event@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-event-org",
        name: "GRPC Sessions Event Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-event-repo",
        name: "GRPC Session Event Repo",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-event-1",
        goal: "Capture output",
        project_id: project.id,
        user_id: user.id
      })

    response =
      SessionsServer.capture_session_event(
        %CaptureSessionEventRequest{
          user_id: user.id,
          session_id: session.session_id,
          payload: "hello from agent",
          stream: "stderr",
          format: "markdown"
        },
        nil
      )

    assert %CaptureSessionEventResponse{} = response
    assert String.starts_with?(response.storage_key, "sessions/#{session.session_id}/events/")

    {:ok, stored_json} = Storage.get(response.storage_key)
    stored_event = Jason.decode!(stored_json)
    response_event = Jason.decode!(response.event_json)

    assert stored_event["type"] == "output"
    assert stored_event["payload"]["text"] == "hello from agent"
    assert stored_event["payload"]["stream"] == "stderr"
    assert stored_event["payload"]["format"] == "markdown"
    assert stored_event["id"] == response_event["id"]
  end

  test "land_session supports epoch batching without landing" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-session-batch@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-session-batch-org",
        name: "GRPC Sessions Batch Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-session-batch-repo",
        name: "GRPC Session Batch Repo",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-grpc-batch-1",
        goal: "Batch land",
        project_id: project.id,
        user_id: user.id
      })

    Mimic.stub(Landing, :land_session, fn _session ->
      flunk("Landing should not be invoked for non-final epoch batches")
    end)

    response =
      SessionsServer.land_session(
        %LandSessionRequest{
          user_id: user.id,
          session_id: session.session_id,
          conversation: [],
          decisions: [],
          files: [
            %FileChange{path: "lib/example.ex", content: "ok\n", change_type: "added"}
          ],
          epoch: 1,
          finalize: false
        },
        nil
      )

    assert %SessionResponse{} = response
    assert response.session.session_id == session.session_id
    assert response.session.status == "active"
    assert response.session.landing_position == 0

    persisted = Sessions.get_session_by_session_id(session.session_id)
    assert persisted.metadata["epoch_batch"] == 1
  end

  defp setup_storage(context) do
    StorageHelper.setup_isolated_storage(context)
  end
end
