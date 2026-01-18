defmodule MicelioWeb.Browser.AccountControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.{Accounts, Projects, Sessions}

  test "shows activity and owned repositories for user accounts", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("public-user@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "public-user-org",
        name: "Public User Org"
      })

    {:ok, public_project} =
      Projects.create_project(%{
        handle: "public-repo",
        name: "Public Repo",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, private_project} =
      Projects.create_project(%{
        handle: "private-repo",
        name: "Private Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, public_session} =
      Sessions.create_session(%{
        session_id: "public-repo-session",
        goal: "Public work",
        project_id: public_project.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(public_session)

    {:ok, private_session} =
      Sessions.create_session(%{
        session_id: "private-repo-session",
        goal: "Private work",
        project_id: private_project.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(private_session)

    conn = get(conn, ~p"/#{user.account.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-activity\""
    assert html =~ "activity-graph"
    assert html =~ "Owned repositories"
    assert html =~ "id=\"account-owned-projects\""
    assert html =~ "id=\"account-projects-list\""
    assert html =~ "account-project-#{public_project.id}"
    assert html =~ "/#{organization.account.handle}/#{public_project.handle}"
    refute html =~ "/#{organization.account.handle}/#{private_project.handle}"
    assert html =~ "aria-label=\"1 contributions\""
  end
end
