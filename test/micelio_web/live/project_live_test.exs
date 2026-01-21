defmodule MicelioWeb.ProjectLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Projects

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{"user_id" => user.id})
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  defp unique_email(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}@example.com"
  end

  test "lists projects for the current user and supports delete", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-live"))
    org_handle = unique_handle("live-org")
    project_handle = unique_handle("live-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Live Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: project_handle,
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
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-create"))
    org_handle = unique_handle("create-org")
    project_handle = unique_handle("live-created")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Create Org",
        llm_models: ["gpt-4.1"],
        llm_default_model: "gpt-4.1"
      })

    conn = login_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    form =
      form(view, "#project-form",
        project: %{
          organization_id: organization.id,
          name: "Live Created",
          handle: project_handle,
          description: "Created from LiveView",
          visibility: "public",
          llm_model: "gpt-4.1"
        }
      )

    render_submit(form)

    project = Projects.get_project_by_handle(organization.id, project_handle)
    assert project.visibility == "public"
    assert project.llm_model == "gpt-4.1"

    assert_redirect(view, ~p"/projects/#{organization.account.handle}/#{project_handle}")
  end

  test "updates a project from the edit form", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-edit"))
    org_handle = unique_handle("edit-org")
    project_handle = unique_handle("edit-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Edit Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: project_handle,
        name: "Edit Project",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project_handle}/edit")

    form =
      form(view, "#project-form",
        project: %{
          name: "Updated Project",
          handle: project_handle,
          description: "Updated",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Projects.get_project(project.id)
    assert updated.visibility == "public"

    assert_redirect(view, ~p"/projects/#{organization.account.handle}/#{project_handle}")
  end

  test "toggles project stars from the show view", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email(unique_email("projects-star"))
    org_handle = unique_handle("star-org")
    project_handle = unique_handle("star-project")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: org_handle,
        name: "Star Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: project_handle,
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
