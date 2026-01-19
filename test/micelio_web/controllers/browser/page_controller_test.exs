defmodule MicelioWeb.Browser.PageControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects

  test "renders popular projects for anonymous users", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "popular-home-#{unique}",
        name: "Popular Home #{unique}"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "popular-home-project-#{unique}",
        name: "Popular Home Project",
        description: "Popular home description",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, star_user} =
      Accounts.get_or_create_user_by_email("popular-home-star-#{unique}@example.com")

    assert {:ok, _} = Projects.star_project(star_user, project)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "popular-projects"
    assert html =~ "popular-project-#{project.id}"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
    assert html =~ "Stars: 1"
  end

  test "shows pagination when more popular projects exist", %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "popular-page-#{unique}",
        name: "Popular Page #{unique}"
      })

    Enum.each(1..7, fn index ->
      {:ok, _} =
        Projects.create_project(%{
          handle: "popular-page-project-#{unique}-#{index}",
          name: "Popular Page Project #{index}",
          description: "Popular page project #{index}",
          organization_id: organization.id,
          visibility: "public"
        })
    end)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "popular-projects-next"
  end
end
