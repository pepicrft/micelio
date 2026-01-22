defmodule Micelio.Admin do
  @moduledoc """
  Admin-only queries and policies for instance oversight.
  """

  import Ecto.Query

  alias Micelio.Accounts.{Organization, User}
  alias Micelio.Projects.Project
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repo
  alias Micelio.Sessions.Session

  @doc """
  Returns the configured list of admin emails.
  """
  def admin_emails do
    :micelio
    |> Application.get_env(:admin_emails, [])
    |> Enum.map(&String.downcase/1)
  end

  @doc """
  Returns true when the user is configured as an instance admin.
  """
  def admin_user?(%User{} = user) do
    email = String.downcase(user.email || "")
    email in admin_emails()
  end

  def admin_user?(_), do: false

  @doc """
  Returns aggregate counts for the admin dashboard.
  """
  def dashboard_stats do
    admin_emails = admin_emails()

    %{
      users: Repo.aggregate(User, :count),
      admin_emails_configured: length(admin_emails),
      admin_users: admin_user_count(admin_emails),
      organizations: Repo.aggregate(Organization, :count),
      projects: Repo.aggregate(Project, :count),
      sessions: Repo.aggregate(Session, :count),
      public_projects:
        Project
        |> where([p], p.visibility == "public")
        |> Repo.aggregate(:count),
      private_projects:
        Project
        |> where([p], p.visibility == "private")
        |> Repo.aggregate(:count)
    }
  end

  @doc """
  Lists the most recently created users with accounts preloaded.
  """
  def list_recent_users(limit \\ 10) when is_integer(limit) and limit > 0 do
    User
    |> join(:left, [u], a in assoc(u, :account))
    |> preload([_u, a], account: a)
    |> order_by([u], desc: u.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists the most recently created organizations with accounts preloaded.
  """
  def list_recent_organizations(limit \\ 10) when is_integer(limit) and limit > 0 do
    Organization
    |> join(:left, [o], a in assoc(o, :account))
    |> preload([_o, a], account: a)
    |> order_by([o], desc: o.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists the most recently created projects with organization/account preloaded.
  """
  def list_recent_projects(limit \\ 10) when is_integer(limit) and limit > 0 do
    Project
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([p], desc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists the most recently created sessions with related user and project data preloaded.
  """
  def list_recent_sessions(limit \\ 10) when is_integer(limit) and limit > 0 do
    Session
    |> join(:left, [s], u in assoc(s, :user))
    |> join(:left, [s, u], p in assoc(s, :project))
    |> join(:left, [s, u, p], o in assoc(p, :organization))
    |> join(:left, [s, u, p, o], a in assoc(o, :account))
    |> preload([_s, u, p, o, a], user: u, project: {p, organization: {o, account: a}})
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns aggregate AI token usage metrics across all prompt requests.
  """
  def usage_dashboard_stats do
    tokens_spent =
      Repo.one(
        from pr in PromptRequest,
          select: fragment("COALESCE(?, 0)", sum(pr.token_count))
      ) || 0

    accepted_prompt_requests =
      Repo.one(
        from pr in PromptRequest,
          where: pr.review_status == :accepted,
          select: count(pr.id)
      ) || 0

    total_prompt_requests =
      Repo.one(
        from pr in PromptRequest,
          select: count(pr.id)
      ) || 0

    %{
      tokens_spent: tokens_spent,
      accepted_prompt_requests: accepted_prompt_requests,
      total_prompt_requests: total_prompt_requests
    }
  end

  @doc """
  Returns per-project usage stats for prompt request token usage.
  """
  def list_project_usage(limit \\ 20) when is_integer(limit) and limit > 0 do
    PromptRequest
    |> join(:inner, [pr], p in assoc(pr, :project))
    |> join(:inner, [pr, p], o in assoc(p, :organization))
    |> join(:inner, [pr, p, o], a in assoc(o, :account))
    |> group_by([_pr, p, _o, a], [p.id, p.name, p.handle, a.handle])
    |> select([pr, p, _o, a], %{
      project_id: p.id,
      project_name: p.name,
      project_handle: p.handle,
      account_handle: a.handle,
      tokens_spent: fragment("COALESCE(?, 0)", sum(pr.token_count)),
      total_prompt_requests: count(pr.id),
      accepted_prompt_requests:
        fragment("SUM(CASE WHEN ? = 'accepted' THEN 1 ELSE 0 END)", pr.review_status)
    })
    |> order_by([pr, _p, _o, _a], [
      desc: fragment("COALESCE(?, 0)", sum(pr.token_count)),
      desc: count(pr.id)
    ])
    |> limit(^limit)
    |> Repo.all()
  end

  defp admin_user_count([]), do: 0

  defp admin_user_count(admin_emails) do
    User
    |> where([u], fragment("lower(?)", u.email) in ^admin_emails)
    |> Repo.aggregate(:count)
  end
end
