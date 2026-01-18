defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  alias MicelioWeb.Browser.ProjectController

  def show(conn, params), do: delegate(conn, params, &ProjectController.show/2)
  def tree(conn, params), do: delegate(conn, params, &ProjectController.tree/2)
  def blob(conn, params), do: delegate(conn, params, &ProjectController.blob/2)
  def blame(conn, params), do: delegate(conn, params, &ProjectController.blame/2)
  def toggle_star(conn, params), do: delegate(conn, params, &ProjectController.toggle_star/2)
  def fork(conn, params), do: delegate(conn, params, &ProjectController.fork/2)

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
