defmodule MicelioWeb.Browser.AdminControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions

  test "denies access to non-admin users", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("user@example.com")

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/admin")

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Controller.get_flash(conn, :error) == "You do not have access to that page."
  end

  test "shows admin dashboard for admins", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")
    {:ok, organization} = Accounts.create_organization(%{name: "Acme", handle: "acme"})

    {:ok, project} =
      Projects.create_project(%{
        name: "Acme Repo",
        handle: "acme-repo",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "session-1",
        goal: "Ship overview",
        project_id: project.id,
        user_id: admin.id
      })

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin")

    html = html_response(conn, 200)
    assert html =~ "Admin dashboard"
    assert html =~ "id=\"admin-dashboard\""
    assert html =~ "id=\"admin-metrics\""
    assert html =~ "id=\"admin-metric-admin-users\""
    assert html =~ "id=\"admin-metric-admin-emails\""
    assert html =~ "id=\"admin-access\""
    assert html =~ "id=\"admin-admins-list\""
    assert html =~ "id=\"admin-email-0\""
    assert html =~ "id=\"admin-users-list\""
    assert html =~ "id=\"admin-organizations-list\""
    assert html =~ "id=\"admin-projects-list\""
    assert html =~ "id=\"admin-sessions-list\""
    assert html =~ "id=\"admin-metric-public-projects\""
    assert html =~ "id=\"admin-metric-private-projects\""
    assert html =~ "id=\"admin-user-#{admin.id}\""
    assert html =~ "id=\"admin-user-role-#{admin.id}\""
    assert html =~ "id=\"admin-organization-#{organization.id}\""
    assert html =~ "id=\"admin-project-#{project.id}\""
    assert html =~ "id=\"admin-session-#{session.id}\""
  end

  test "shows empty states when there is no activity yet", %{conn: conn} do
    {:ok, admin} = Accounts.get_or_create_user_by_email("admin@example.com")

    conn =
      conn
      |> log_in_user(admin)
      |> get(~p"/admin")

    html = html_response(conn, 200)
    assert html =~ "No organizations yet."
    assert html =~ "No projects yet."
    assert html =~ "No sessions yet."
  end
end
