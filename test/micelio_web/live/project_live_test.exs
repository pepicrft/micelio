defmodule MicelioWeb.ProjectLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Projects

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{user_id: user.id})
  end

  test "lists projects for the current user and supports delete", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("projects-live@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "live-org",
        name: "Live Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "live-project",
        name: "Live Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/projects")

    assert has_element?(view, "#new-project-link")
    assert has_element?(view, "#project-view-#{project.id}")

    view
    |> element("#project-delete-#{project.id}")
    |> render_click()

    refute has_element?(view, "#project-view-#{project.id}")
    assert Projects.get_project(project.id) == nil
  end

  test "creates a project from the new form", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("projects-create@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "create-org",
        name: "Create Org"
      })

    conn = login_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    form =
      form(view, "#project-form",
        project: %{
          organization_id: organization.id,
          name: "Live Created",
          handle: "live-created",
          description: "Created from LiveView",
          visibility: "public"
        }
      )

    render_submit(form)

    project = Projects.get_project_by_handle(organization.id, "live-created")
    assert project.visibility == "public"

    assert_redirect(view, ~p"/projects/#{organization.account.handle}/live-created")
  end

  test "updates a project from the edit form", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("projects-edit@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "edit-org",
        name: "Edit Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "edit-project",
        name: "Edit Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/edit-project/edit")

    form =
      form(view, "#project-form",
        project: %{
          name: "Updated Project",
          handle: "edit-project",
          description: "Updated",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Projects.get_project(project.id)
    assert updated.visibility == "public"

    assert_redirect(view, ~p"/projects/#{organization.account.handle}/edit-project")
  end

  test "toggles project stars from the show view", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("projects-star@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "star-org",
        name: "Star Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "star-project",
        name: "Star Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}")

    assert has_element?(view, "#project-star-toggle")
    assert element(view, "#project-stars-count") |> render() =~ "Stars: 0"

    view
    |> element("#project-star-toggle")
    |> render_click()

    assert Projects.project_starred?(user, project)
    assert Projects.count_project_stars(project) == 1
    assert element(view, "#project-stars-count") |> render() =~ "Stars: 1"

    view
    |> element("#project-star-toggle")
    |> render_click()

    refute Projects.project_starred?(user, project)
    assert Projects.count_project_stars(project) == 0
    assert element(view, "#project-stars-count") |> render() =~ "Stars: 0"
  end
end
