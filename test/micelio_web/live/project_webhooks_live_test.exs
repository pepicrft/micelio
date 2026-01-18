defmodule MicelioWeb.RepositoryWebhooksLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Webhooks

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{user_id: user.id})
  end

  test "creates a webhook from the webhooks page", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-webhooks@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "webhooks-org",
        name: "Webhooks Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "webhooks-repo",
        name: "Webhooks Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks")

    assert has_element?(view, "#webhook-form")

    form =
      form(view, "#webhook-form",
        webhook: %{
          url: "https://hooks.example.com/push",
          events: ["push"],
          secret: "super-secret"
        }
      )

    render_submit(form)

    [webhook] = Webhooks.list_webhooks_for_project(repository.id)
    assert webhook.url == "https://hooks.example.com/push"
    assert webhook.events == ["push"]
  end

  test "toggles and deletes a webhook", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-webhooks-toggle@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "webhooks-toggle-org",
        name: "Webhooks Toggle Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "webhooks-toggle-repo",
        name: "Webhooks Toggle Repo",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, webhook} =
      Webhooks.create_webhook(%{
        project_id: repository.id,
        url: "https://hooks.example.com/landing",
        events: ["session.landed"],
        active: true
      })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks")

    view
    |> element("#webhook-toggle-#{webhook.id}")
    |> render_click()

    updated = Webhooks.get_webhook_for_project(repository.id, webhook.id)
    assert updated.active == false

    view
    |> element("#webhook-delete-#{webhook.id}")
    |> render_click()

    assert Webhooks.get_webhook_for_project(repository.id, webhook.id) == nil
  end

  test "requires authentication", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("repo-webhooks-auth@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "webhooks-auth-org",
        name: "Webhooks Auth Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "webhooks-auth-repo",
        name: "Webhooks Auth Repo",
        organization_id: organization.id
      })

    assert {:error, {:redirect, %{to: "/auth/login"}}} =
             live(
               conn,
               ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks"
             )
  end

  test "requires admin access", %{conn: conn} do
    {:ok, owner} = Accounts.get_or_create_user_by_email("repo-webhooks-owner@example.com")
    {:ok, member} = Accounts.get_or_create_user_by_email("repo-webhooks-member@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "webhooks-access-org",
        name: "Webhooks Access Org"
      })

    {:ok, repository} =
      Projects.create_project(%{
        handle: "webhooks-access-repo",
        name: "Webhooks Access Repo",
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
             live(
               conn,
               ~p"/#{organization.account.handle}/#{repository.handle}/settings/webhooks"
             )

    assert redirect_to == ~p"/#{organization.account.handle}/#{repository.handle}"
  end
end
