defmodule MicelioWeb.Browser.AccountController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Repo
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  def show(conn, %{"account" => account_handle}) do
    case conn.assigns.selected_account do
      %Accounts.Account{} = account ->
        organization =
          if Accounts.Account.organization?(account) do
            account |> Repo.preload(:organization) |> Map.get(:organization)
          end

        user =
          if is_binary(account.user_id) do
            Accounts.get_user_with_account(account.user_id)
          end

        projects =
          cond do
            organization ->
              Projects.list_public_projects_for_organization(account.organization_id)

            user ->
              user
              |> Accounts.list_organizations_for_user_with_role("admin")
              |> Enum.map(& &1.id)
              |> Projects.list_public_projects_for_organizations()

            true ->
              []
          end

        activity_counts =
          if user do
            Sessions.activity_counts_for_user_public(user)
          else
            %{}
          end

        title =
          if organization && organization.name && organization.name != "" do
            organization.name
          else
            account.handle
          end

        description =
          if user do
            "Repositories and activity for @#{account.handle}."
          else
            "Projects for @#{account.handle}."
          end

        conn
        |> PageMeta.put(
          title_parts: [title],
          description: description,
          canonical_url: url(~p"/#{account_handle}")
        )
        |> assign(:account, account)
        |> assign(:organization, organization)
        |> assign(:user, user)
        |> assign(:projects, projects)
        |> assign(:projects_title, if(user, do: "Owned repositories", else: "Repositories"))
        |> assign(:empty_message, if(user, do: "No public repositories yet.", else: "No projects yet."))
        |> assign(:activity_counts, activity_counts)
        |> render(:show)

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
