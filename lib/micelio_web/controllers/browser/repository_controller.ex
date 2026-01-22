defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  alias Micelio.Authorization
  alias Micelio.Projects
  alias MicelioWeb.Badges.ProjectBadge
  alias MicelioWeb.Browser.ProjectController

  def show(conn, params), do: delegate(conn, params, &ProjectController.show/2)
  def tree(conn, params), do: delegate(conn, params, &ProjectController.tree/2)
  def blob(conn, params), do: delegate(conn, params, &ProjectController.blob/2)
  def blame(conn, params), do: delegate(conn, params, &ProjectController.blame/2)
  def toggle_star(conn, params), do: delegate(conn, params, &ProjectController.toggle_star/2)
  def fork(conn, params), do: delegate(conn, params, &ProjectController.fork/2)
  def contribute_tokens(conn, params), do: delegate(conn, params, &ProjectController.contribute_tokens/2)

  def badge(conn, _params) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:project_read, conn.assigns.current_user, project) do
      stars = Projects.count_project_stars(project)
      label = "#{account.handle}/#{project.handle}"
      message = "#{stars} stars"

      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "public, max-age=300")
      |> send_resp(200, ProjectBadge.render(label, message))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp delegate(conn, %{"repository" => repository_handle} = params, fun) do
    params =
      params
      |> Map.put("project", repository_handle)
      |> Map.delete("repository")

    conn
    |> put_view(MicelioWeb.Browser.ProjectHTML)
    |> ensure_selected_project()
    |> fun.(params)
  end

  defp delegate(conn, params, fun) do
    conn
    |> put_view(MicelioWeb.Browser.ProjectHTML)
    |> ensure_selected_project()
    |> fun.(params)
  end

  defp ensure_selected_project(conn) do
    cond do
      Map.has_key?(conn.assigns, :selected_project) ->
        conn

      Map.has_key?(conn.assigns, :selected_repository) ->
        assign(conn, :selected_project, conn.assigns.selected_repository)

      true ->
        conn
    end
  end
end
