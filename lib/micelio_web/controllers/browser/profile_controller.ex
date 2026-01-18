defmodule MicelioWeb.Browser.ProfileController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  def show(conn, _params) do
    user = conn.assigns.current_user
    activity_counts = Sessions.activity_counts_for_user(user)
    starred_projects = Projects.list_starred_projects_for_user(user)
    passkeys = Accounts.list_passkeys_for_user(user)

    owned_projects =
      user
      |> Accounts.list_organizations_for_user_with_role("admin")
      |> Enum.map(& &1.id)
      |> Projects.list_projects_for_organizations()

    conn
    |> PageMeta.put(
      title_parts: ["@#{user.account.handle}"],
      description: "Account settings and personal preferences.",
      canonical_url: url(~p"/account")
    )
    |> render(:show,
      user: user,
      activity_counts: activity_counts,
      passkeys: passkeys,
      starred_projects: starred_projects,
      owned_projects: owned_projects
    )
  end
end
