defmodule MicelioWeb.Browser.ProfileControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions

  setup :register_and_log_in_user

  test "shows profile page with devices link", %{conn: conn, user: user} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "@#{user.account.handle}"
    assert html =~ "id=\"account-devices-link\""
  end

  test "shows navbar user link on authenticated pages", %{conn: conn, user: _user} do
    conn = get(conn, ~p"/account/devices")
    html = html_response(conn, 200)

    assert html =~ "class=\"navbar-user-avatar\""
    assert html =~ "id=\"navbar-user\""
    assert html =~ "href=\"/account\""
    assert html =~ "gravatar.com/avatar/"
  end

  test "shows favorites list for starred projects", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization(%{handle: "favorite-org", name: "Favorite Org"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "favorite-project",
        name: "Favorite Project",
        organization_id: organization.id,
        visibility: "public"
      })

    assert {:ok, _star} = Projects.star_project(user, project)

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-favorites\""
    assert html =~ "id=\"account-favorites-list\""
    assert html =~ "favorite-#{project.id}"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
  end

  test "shows owned repositories list for admin organizations", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "owned-org",
        name: "Owned Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "owned-project",
        name: "Owned Project",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-owned-projects\""
    assert html =~ "id=\"account-owned-projects-list\""
    assert html =~ "owned-project-#{project.id}"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
  end

  test "shows activity graph for landed sessions", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "activity-org",
        name: "Activity Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "activity-project",
        name: "Activity Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "activity-session",
        goal: "Ship activity",
        project_id: project.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(session)

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-activity\""
    assert html =~ "class=\"account-section-title\">Activity"
    assert html =~ "activity-graph"
    assert html =~ "aria-label=\"1 contributions\""
    assert html =~ "activity-graph-legend"
  end
end
