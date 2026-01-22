defmodule Micelio.Sessions.EventStreamTest do
  use Micelio.DataCase

  alias Micelio.{Accounts, Projects, Sessions}
  alias Micelio.StorageHelper

  setup :setup_storage

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("streamer@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "stream-org",
        name: "Stream Org"
      })

    {:ok, project} =
      Projects.create_project(
        %{
          handle: "stream-project",
          name: "Stream Project",
          organization_id: organization.id
        },
        user: user
      )

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "stream-session-1",
        goal: "Stream events",
        project_id: project.id,
        user_id: user.id
      })

    %{session: session}
  end

  test "list_session_events filters by type and cursor", %{session: session} do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)
    t1 = DateTime.add(now, -3, :second)
    t2 = DateTime.add(now, -2, :second)
    t3 = DateTime.add(now, -1, :second)

    {:ok, _} =
      Sessions.capture_session_event(session, %{
        type: "status",
        payload: %{state: "running"}
      },
        timestamp: t1
      )

    {:ok, _} =
      Sessions.capture_session_event(session, %{
        type: "output",
        payload: %{text: "first", stream: "stdout", format: "text"}
      },
        timestamp: t2
      )

    {:ok, _} =
      Sessions.capture_session_event(session, %{
        type: "output",
        payload: %{text: "second", stream: "stdout", format: "text"}
      },
        timestamp: t3
      )

    assert {:ok, events} = Sessions.list_session_events(session.session_id, types: ["output"])
    assert Enum.map(events, & &1.event["payload"]["text"]) == ["first", "second"]

    after_key = hd(events).storage_key
    assert {:ok, [later]} = Sessions.list_session_events(session.session_id, after: after_key)
    assert later.event["payload"]["text"] == "second"

    since = DateTime.to_unix(t2, :millisecond)
    assert {:ok, [since_event]} = Sessions.list_session_events(session.session_id, since: since)
    assert since_event.event["payload"]["text"] == "second"
  end

  defp setup_storage(context) do
    StorageHelper.setup_isolated_storage(context)
  end
end
