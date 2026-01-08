defmodule Micelio.Projects do
  @moduledoc """
  The Projects context handles project management.
  Projects belong to accounts and have a unique handle within each account.
  """

  import Ecto.Query

  alias Micelio.Projects.Project
  alias Micelio.Repo

  @doc """
  Gets a project by ID.
  """
  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a project by ID with account preloaded.
  """
  def get_project_with_account(id) do
    Project
    |> Repo.get(id)
    |> Repo.preload(:account)
  end

  @doc """
  Gets a project by account ID and handle (case-insensitive).
  """
  def get_project_by_handle(account_id, handle) do
    Project
    |> where([p], p.account_id == ^account_id)
    |> where([p], fragment("lower(?)", p.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Lists all projects for an account.
  """
  def list_projects_for_account(account_id) do
    Project
    |> where([p], p.account_id == ^account_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Creates a new project.
  """
  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc """
  Checks if a handle is available for a given account.
  """
  def handle_available?(account_id, handle) do
    is_nil(get_project_by_handle(account_id, handle))
  end
end
