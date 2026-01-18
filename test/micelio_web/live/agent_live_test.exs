defmodule MicelioWeb.AgentLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.{Accounts, Projects, Sessions}

  test "renders active agent sessions for public projects", %{conn: conn} do
    %{user: user, organization: organization, project: project} = create_public_project()

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-progress-session",
        goal: "Stream live agent updates",
        project_id: project.id,
        user_id: user.id,
        conversation: [
          %{"role" => "user", "content" => "Kick off work"},
          %{"role" => "assistant", "content" => "Working on it"}
        ],
        decisions: [%{"decision" => "Track progress", "reasoning" => "Visibility"}]
      })

    {:ok, _change} =
      Sessions.create_session_change(%{
        session_id: session.id,
        file_path: "lib/progress.ex",
        change_type: "added",
        content: "defmodule Progress do\nend\n"
      })

    {:ok, view, _html} =
      live(conn, "/#{organization.account.handle}/#{project.handle}/agents")

    assert has_element?(view, "#agent-progress")
    assert has_element?(view, "#agent-progress-list")
    assert has_element?(view, "#agent-session-#{session.id}")

    assert has_element?(
             view,
             "#agent-session-#{session.id} .agent-progress-goal",
             session.goal
           )
  end

  test "shows empty state when no active sessions exist", %{conn: conn} do
    %{organization: organization, project: project} = create_public_project()

    {:ok, view, _html} =
      live(conn, "/#{organization.account.handle}/#{project.handle}/agents")

    assert has_element?(view, "#agent-progress-empty")
  end

  test "redirects when project is private for anonymous viewer", %{conn: conn} do
    %{organization: organization, project: project} = create_private_project()

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => "Project not found."}}}} =
             live(conn, "/#{organization.account.handle}/#{project.handle}/agents")
  end

  defp create_public_project do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} =
      Accounts.get_or_create_user_by_email("agent-progress-#{unique_suffix}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-org-#{unique_suffix}",
        name: "Agent Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "agent-project-#{unique_suffix}",
        name: "Agent Project",
        description: "Public project",
        organization_id: organization.id,
        visibility: "public"
      })

    %{user: user, organization: organization, project: project}
  end

  defp create_private_project do
    unique_suffix = Integer.to_string(System.unique_integer([:positive]))

    {:ok, user} =
      Accounts.get_or_create_user_by_email("agent-private-#{unique_suffix}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-private-org-#{unique_suffix}",
        name: "Agent Private Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "agent-private-project-#{unique_suffix}",
        name: "Agent Private Project",
        description: "Private project",
        organization_id: organization.id,
        visibility: "private"
      })

    %{user: user, organization: organization, project: project}
  end
end
