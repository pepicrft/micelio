defmodule Micelio.GRPC.SessionsServerTest do
  use Micelio.DataCase, async: true

  import Mimic

  alias Micelio.Accounts
  alias Micelio.GRPC.Sessions.V1.LandSessionRequest
  alias Micelio.GRPC.Sessions.V1.SessionResponse
  alias Micelio.GRPC.Sessions.V1.SessionService.Server, as: SessionsServer
  alias Micelio.Hif.Landing
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Webhooks

  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Landing)
    Mimic.copy(Webhooks)
    :ok
  end

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

    expect(Webhooks, :dispatch_session_landed, fn dispatched_project, dispatched_session, position ->
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
end
