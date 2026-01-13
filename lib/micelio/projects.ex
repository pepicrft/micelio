defmodule Micelio.Projects do
  @moduledoc """
  The Projects context handles project management.
  Projects belong to organizations and have a unique handle within each organization.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Projects.Project
  alias Micelio.Repo

  @doc """
  Gets a project by ID.
  """
  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a project by ID with organization preloaded.
  """
  def get_project_with_organization(id) do
    Project
    |> Repo.get(id)
    |> Repo.preload(:organization)
  end

  @doc """
  Gets a project by organization ID and handle (case-insensitive).
  """
  def get_project_by_handle(organization_id, handle) do
    Project
    |> where([p], p.organization_id == ^organization_id)
    |> where([p], fragment("lower(?)", p.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Lists all projects for an organization.
  """
  def list_projects_for_organization(organization_id) do
    Project
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Lists all projects.
  """
  def list_projects do
    Repo.all(Project)
  end

  @doc """
  Lists all projects for the organizations a user belongs to.
  Projects are ordered by organization handle and project name.
  """
  def list_projects_for_user(user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    list_projects_for_organizations(organization_ids)
  end

  @doc """
  Lists all projects for a set of organization IDs.
  """
  def list_projects_for_organizations([]), do: []

  def list_projects_for_organizations(organization_ids) do
    Project
    |> where([p], p.organization_id in ^organization_ids)
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([p, o, a], organization: {o, account: a})
    |> order_by([_p, _o, a], asc: a.handle)
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
  Checks if a handle is available for a given organization.
  """
  def handle_available?(organization_id, handle) do
    is_nil(get_project_by_handle(organization_id, handle))
  end

  @doc """
  Gets a project by organization handle and project handle for a user.
  """
  def get_project_for_user_by_handle(user, organization_handle, project_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Project{} = project <- get_project_by_handle(organization.id, project_handle) do
      {:ok, project, organization}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
end
