defmodule MicelioWeb.Browser.ProfileController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  def show(conn, _params) do
    user = conn.assigns.current_user

    profile_form =
      user
      |> Accounts.change_user_profile()
      |> to_form(as: :user)

    conn
    |> put_profile_meta(user)
    |> render(:show, Map.merge(profile_assigns(user), %{user: user, profile_form: profile_form}))
  end

  def update(conn, %{"user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Profile updated.")
        |> redirect(to: ~p"/account")

      {:error, changeset} ->
        profile_form = to_form(%{changeset | action: :update}, as: :user)

        conn
        |> put_profile_meta(user)
        |> render(
          :show,
          Map.merge(profile_assigns(user), %{user: user, profile_form: profile_form})
        )
    end
  end

  defp profile_assigns(user) do
    activity_counts = Sessions.activity_counts_for_user(user)
    starred_projects = Projects.list_starred_projects_for_user(user)
    passkeys = Accounts.list_passkeys_for_user(user)
    organizations = Accounts.list_organizations_for_user_with_member_counts(user)

    owned_projects =
      user
      |> Accounts.list_organizations_for_user_with_role("admin")
      |> Enum.map(& &1.id)
      |> Projects.list_projects_for_organizations()

    %{
      activity_counts: activity_counts,
      passkeys: passkeys,
      starred_projects: starred_projects,
      owned_projects: owned_projects,
      organizations: organizations
    }
  end

  defp put_profile_meta(conn, user) do
    PageMeta.put(conn,
      title_parts: ["@#{user.account.handle}"],
      description: "Account settings and personal preferences.",
      canonical_url: url(~p"/account")
    )
  end
end
