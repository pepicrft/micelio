defmodule Micelio.NotificationsTest do
  use Micelio.DataCase, async: true

  import Swoosh.TestAssertions

  alias Micelio.Accounts
  alias Micelio.Notifications
  alias Micelio.Projects
  alias Micelio.Sessions

  test "dispatch_session_landed/3 sends session landed emails to organization members" do
    {:ok, owner} = Accounts.get_or_create_user_by_email("owner@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("member@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{handle: "acme", name: "Acme"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "user"
      })

    {:ok, project} =
      Projects.create_project(%{
        name: "Acme Docs",
        handle: "docs",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-1",
        goal: "Ship docs",
        project_id: project.id,
        user_id: owner.id
      })

    {:ok, landed_session} = Sessions.land_session(session, %{})

    :ok = Notifications.dispatch_session_landed(project, landed_session, async: false)

    assert_emails_sent([
      %{to: "member@example.com", subject: ~r/\[acme\/docs\]/},
      %{to: "owner@example.com", subject: ~r/\[acme\/docs\]/}
    ])
  end

  test "dispatch_project_starred/3 sends star emails to organization members" do
    {:ok, owner} = Accounts.get_or_create_user_by_email("owner-star@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("member-star@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{handle: "acme-star", name: "Acme Star"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "user"
      })

    {:ok, project} =
      Projects.create_project(%{
        name: "Star Docs",
        handle: "docs",
        organization_id: organization.id,
        visibility: "private"
      })

    :ok = Notifications.dispatch_project_starred(project, member, async: false)

    assert_emails_sent([
      %{to: "member-star@example.com", subject: ~r/\[acme-star\/docs\].*starred/i},
      %{to: "owner-star@example.com", subject: ~r/\[acme-star\/docs\].*starred/i}
    ])
  end
end
