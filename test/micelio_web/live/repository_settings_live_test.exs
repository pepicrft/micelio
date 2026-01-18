defmodule MicelioWeb.RepositorySettingsLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Projects

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{user_id: user.id})
  end

  test "updates repository settings from the settings page", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-settings@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "settings-org",
        name: "Settings Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "settings-repo",
        name: "Settings Repo",
        description: "Original description",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    assert has_element?(view, "#repository-settings-form")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: "Updated Repo",
          description: "Updated description",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Projects.get_project(repository.id)
    assert updated.name == "Updated Repo"
    assert updated.description == "Updated description"
    assert updated.visibility == "public"

    assert_redirect(view, ~p"/#{organization.account.handle}/#{repository.handle}")
  end

  test "ignores handle changes from the settings page", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-settings-handle@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "handle-settings-org",
        name: "Handle Settings Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "handle-settings-repo",
        name: "Handle Settings Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: "Handle Settings Repo Updated",
          handle: "hijacked-handle",
          visibility: "public"
        }
      )

    render_submit(form)

    updated = Projects.get_project(repository.id)
    assert updated.handle == "handle-settings-repo"
    assert updated.name == "Handle Settings Repo Updated"
  end

  test "requires authentication", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-settings-auth@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "auth-settings-org",
        name: "Auth Settings Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "auth-settings-repo",
        name: "Auth Settings Repo",
        organization_id: organization.id
      })

    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")
  end

  test "requires admin access", %{conn: conn} do
    {:ok, owner} = Accounts.get_or_create_user_by_email("repo-settings-owner@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("repo-settings-member@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "settings-access-org",
        name: "Settings Access Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "settings-access-repo",
        name: "Settings Access Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "user"
      })

    conn = login_user(conn, member)

    assert {:error,
            {:live_redirect,
             %{
               to: redirect_to,
               flash: %{"error" => "You do not have access to this repository."}
             }}} =
             live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    assert redirect_to == ~p"/#{organization.account.handle}/#{repository.handle}"
  end

  test "shows validation errors when required fields are missing", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-settings-errors@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "settings-errors-org",
        name: "Settings Errors Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "settings-errors-repo",
        name: "Settings Errors Repo",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    refute has_element?(view, "#repository-settings-form .form-error")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: ""
        }
      )

    render_change(form)

    assert has_element?(view, "#repository-settings-form .form-error")
  end

  test "keeps repository param names after submit errors", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-settings-form-name@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "settings-form-name-org",
        name: "Settings Form Name Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "settings-form-name-repo",
        name: "Settings Form Name Repo",
        organization_id: organization.id
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings")

    form =
      form(view, "#repository-settings-form",
        repository: %{
          name: ""
        }
      )

    render_submit(form)

    assert has_element?(view, "input[name='repository[name]']")
    assert has_element?(view, "textarea[name='repository[description]']")
  end
end
