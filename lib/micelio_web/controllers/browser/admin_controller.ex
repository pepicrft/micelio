defmodule MicelioWeb.Browser.AdminController do
  use MicelioWeb, :controller

  alias Micelio.Admin
  alias MicelioWeb.PageMeta

  def index(conn, _params) do
    stats = Admin.dashboard_stats()
    admin_emails = Admin.admin_emails()
    recent_users = Admin.list_recent_users()
    recent_organizations = Admin.list_recent_organizations()
    recent_projects = Admin.list_recent_projects()
    recent_sessions = Admin.list_recent_sessions()

    conn
    |> PageMeta.put(
      title_parts: ["Admin dashboard"],
      description: "Instance metrics and recent activity.",
      canonical_url: url(~p"/admin")
    )
    |> render(:index,
      stats: stats,
      admin_emails: admin_emails,
      recent_users: recent_users,
      recent_organizations: recent_organizations,
      recent_projects: recent_projects,
      recent_sessions: recent_sessions
    )
  end

  def usage(conn, _params) do
    usage_stats = Admin.usage_dashboard_stats()
    usage_projects = Admin.list_project_usage()

    conn
    |> PageMeta.put(
      title_parts: ["Usage dashboard"],
      description: "Token usage and value delivered across prompt requests.",
      canonical_url: url(~p"/admin/usage")
    )
    |> render(:usage,
      usage_stats: usage_stats,
      usage_projects: usage_projects
    )
  end
end
