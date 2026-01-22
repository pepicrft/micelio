defmodule MicelioWeb.Browser.AccountController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Activity
  alias Micelio.Projects
  alias Micelio.Repo
  alias Micelio.Reputation
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  def show(conn, %{"account" => account_handle} = params) do
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

        organization_ids =
          if user do
            user
            |> Accounts.list_organizations_for_user_with_role("admin")
            |> Enum.map(& &1.id)
          else
            []
          end

        projects =
          cond do
            organization ->
              Projects.list_public_projects_for_organization(account.organization_id)

            user ->
              Projects.list_public_projects_for_organizations(organization_ids)

            true ->
              []
          end

        activity_counts =
          if user do
            Sessions.activity_counts_for_user_public(user)
          else
            %{}
          end

        organization_admin? =
          if organization && conn.assigns[:current_user] do
            Accounts.user_role_in_organization?(
              conn.assigns.current_user,
              organization.id,
              "admin"
            )
          else
            false
          end

        {activity_items, activity_has_more, activity_next_before} =
          if user do
            activity_before = parse_activity_before(params)

            activity =
              Activity.list_user_activity_public(user, organization_ids, before: activity_before)

            next_before =
              case List.last(activity.items) do
                nil -> nil
                last -> DateTime.to_iso8601(last.occurred_at)
              end

            {activity.items, activity.has_more?, next_before}
          else
            {[], false, nil}
          end

        title =
          if organization && organization.name && organization.name != "" do
            organization.name
          else
            account.handle
          end

        reputation =
          if user do
            Reputation.trust_score_for_user(user)
          end

        description =
          if user do
            "Projects and activity for @#{account.handle}."
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
        |> assign(:projects_title, "Projects")
        |> assign(
          :empty_message,
          if(user, do: "No public projects yet.", else: "No projects yet.")
        )
        |> assign(:reputation, reputation)
        |> assign(:organization_admin?, organization_admin?)
        |> assign(:activity_counts, activity_counts)
        |> assign(:activity_items, activity_items)
        |> assign(:activity_has_more, activity_has_more)
        |> assign(:activity_next_before, activity_next_before)
        |> render(:show)

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp parse_activity_before(%{"before" => before_param}) when is_binary(before_param) do
    case DateTime.from_iso8601(before_param) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _ -> default_activity_before()
    end
  end

  defp parse_activity_before(_params) do
    default_activity_before()
  end

  defp default_activity_before do
    DateTime.utc_now()
    |> DateTime.add(1, :second)
    |> DateTime.truncate(:second)
  end
end
