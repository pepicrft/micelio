defmodule MicelioWeb.Browser.ProjectController do
  use MicelioWeb, :controller

  alias Micelio.Projects
  alias Micelio.Projects.Project

  @doc """
  Lists all projects for the current user's account.
  """
  def index(conn, _params) do
    account = conn.assigns.current_user.account
    projects = Projects.list_projects_for_account(account.id)
    render(conn, :index, projects: projects, account: account)
  end

  @doc """
  Renders the new project form.
  """
  def new(conn, _params) do
    changeset = Projects.change_project(%Project{})
    render(conn, :new, changeset: changeset)
  end

  @doc """
  Creates a new project.
  """
  def create(conn, %{"project" => project_params}) do
    account = conn.assigns.current_user.account

    attrs =
      project_params
      |> Map.put("account_id", account.id)

    case Projects.create_project(attrs) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Project created successfully!")
        |> redirect(to: ~p"/projects/#{project.handle}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  @doc """
  Shows a project.
  """
  def show(conn, %{"handle" => handle}) do
    account = conn.assigns.current_user.account

    case Projects.get_project_by_handle(account.id, handle) do
      nil ->
        conn
        |> put_flash(:error, "Project not found.")
        |> redirect(to: ~p"/projects")

      project ->
        render(conn, :show, project: project, account: account)
    end
  end

  @doc """
  Renders the edit project form.
  """
  def edit(conn, %{"handle" => handle}) do
    account = conn.assigns.current_user.account

    case Projects.get_project_by_handle(account.id, handle) do
      nil ->
        conn
        |> put_flash(:error, "Project not found.")
        |> redirect(to: ~p"/projects")

      project ->
        changeset = Projects.change_project(project)
        render(conn, :edit, project: project, changeset: changeset)
    end
  end

  @doc """
  Updates a project.
  """
  def update(conn, %{"handle" => handle, "project" => project_params}) do
    account = conn.assigns.current_user.account

    case Projects.get_project_by_handle(account.id, handle) do
      nil ->
        conn
        |> put_flash(:error, "Project not found.")
        |> redirect(to: ~p"/projects")

      project ->
        case Projects.update_project(project, project_params) do
          {:ok, updated_project} ->
            conn
            |> put_flash(:info, "Project updated successfully!")
            |> redirect(to: ~p"/projects/#{updated_project.handle}")

          {:error, changeset} ->
            render(conn, :edit, project: project, changeset: changeset)
        end
    end
  end

  @doc """
  Deletes a project.
  """
  def delete(conn, %{"handle" => handle}) do
    account = conn.assigns.current_user.account

    case Projects.get_project_by_handle(account.id, handle) do
      nil ->
        conn
        |> put_flash(:error, "Project not found.")
        |> redirect(to: ~p"/projects")

      project ->
        {:ok, _} = Projects.delete_project(project)

        conn
        |> put_flash(:info, "Project deleted successfully.")
        |> redirect(to: ~p"/projects")
    end
  end
end
