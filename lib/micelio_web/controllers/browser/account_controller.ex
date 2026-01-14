defmodule MicelioWeb.Browser.AccountController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Repo
  alias MicelioWeb.PageMeta

  def show(conn, %{"account" => account_handle}) do
    case conn.assigns.selected_account do
      %Accounts.Account{} = account ->
        organization =
          if Accounts.Account.organization?(account) do
            account |> Repo.preload(:organization) |> Map.get(:organization)
          end

        projects =
          if is_binary(account.organization_id) do
            Projects.list_projects_for_organization(account.organization_id)
          else
            []
          end

        title =
          if organization && organization.name && organization.name != "" do
            organization.name
          else
            account.handle
          end

        conn
        |> PageMeta.put(
          title_parts: [title],
          description: "Projects for @#{account.handle}.",
          canonical_url: url(~p"/#{account_handle}")
        )
        |> assign(:account, account)
        |> assign(:organization, organization)
        |> assign(:projects, projects)
        |> render(:show)

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end
end
