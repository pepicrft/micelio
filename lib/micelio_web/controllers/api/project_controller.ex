defmodule MicelioWeb.API.ProjectController do
  use MicelioWeb, :controller

  alias Micelio.{Accounts, Projects}
  alias Micelio.OAuth.AccessTokens

  action_fallback MicelioWeb.API.FallbackController

  # Helper to extract bearer token
  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  # Helper to verify token and get user
  defp authenticate(conn) do
    with {:ok, token} <- get_bearer_token(conn),
         %Boruta.Oauth.Token{} = access_token <- AccessTokens.get_by(value: token),
         user when not is_nil(user) <- Accounts.get_user(access_token.sub) do
      {:ok, user}
    else
      {:error, :no_token} -> {:error, :unauthorized}
      nil -> {:error, :unauthorized}
      _ -> {:error, :unauthorized}
    end
  end

  @doc """
  List projects for an organization
  GET /api/projects?organization=handle
  """
  def index(conn, %{"organization" => org_handle}) do
    with {:ok, user} <- authenticate(conn),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      projects = Projects.list_projects_for_organization(organization.id)

      conn
      |> put_status(:ok)
      |> json(%{
        projects:
          Enum.map(projects, fn project ->
            %{
              id: project.id,
              handle: project.handle,
              name: project.name,
              description: project.description,
              organization_handle: org_handle,
              inserted_at: project.inserted_at,
              updated_at: project.updated_at
            }
          end)
      })
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  def index(_conn, _params) do
    {:error, :bad_request}
  end

  @doc """
  Get a single project
  GET /api/projects/:organization/:handle
  """
  def show(conn, %{"organization" => org_handle, "handle" => project_handle}) do
    with {:ok, user} <- authenticate(conn),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, project_handle) do
      conn
      |> put_status(:ok)
      |> json(%{
        project: %{
          id: project.id,
          handle: project.handle,
          name: project.name,
          description: project.description,
          organization_handle: org_handle,
          inserted_at: project.inserted_at,
          updated_at: project.updated_at
        }
      })
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  @doc """
  Create a new project
  POST /api/projects
  Body: {
    "organization": "org-handle",
    "handle": "project-handle",
    "name": "Project Name",
    "description": "Optional description"
  }
  """
  def create(conn, params) do
    with {:ok, user} <- authenticate(conn),
         {:ok, org_handle} <- Map.fetch(params, "organization"),
         {:ok, handle} <- Map.fetch(params, "handle"),
         {:ok, name} <- Map.fetch(params, "name"),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      attrs = %{
        handle: handle,
        name: name,
        description: Map.get(params, "description"),
        organization_id: organization.id
      }

      case Projects.create_project(attrs) do
        {:ok, project} ->
          conn
          |> put_status(:created)
          |> json(%{
            project: %{
              id: project.id,
              handle: project.handle,
              name: project.name,
              description: project.description,
              organization_handle: org_handle,
              inserted_at: project.inserted_at,
              updated_at: project.updated_at
            }
          })

        {:error, changeset} ->
          {:error, {:validation, changeset}}
      end
    else
      :error -> {:error, :bad_request}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  @doc """
  Update a project
  PUT /api/projects/:organization/:handle
  Body: {
    "name": "New Name",
    "description": "New description",
    "handle": "new-handle"  // optional, to rename
  }
  """
  def update(conn, %{"organization" => org_handle, "handle" => project_handle} = params) do
    with {:ok, user} <- authenticate(conn),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, project_handle) do
      attrs = %{
        name: Map.get(params, "name", project.name),
        description: Map.get(params, "description"),
        handle: Map.get(params, "new_handle", project.handle)
      }

      case Projects.update_project(project, attrs) do
        {:ok, updated} ->
          conn
          |> put_status(:ok)
          |> json(%{
            project: %{
              id: updated.id,
              handle: updated.handle,
              name: updated.name,
              description: updated.description,
              organization_handle: org_handle,
              inserted_at: updated.inserted_at,
              updated_at: updated.updated_at
            }
          })

        {:error, changeset} ->
          {:error, {:validation, changeset}}
      end
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  @doc """
  Delete a project
  DELETE /api/projects/:organization/:handle
  """
  def delete(conn, %{"organization" => org_handle, "handle" => project_handle}) do
    with {:ok, user} <- authenticate(conn),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, project_handle),
         {:ok, _} <- Projects.delete_project(project) do
      conn
      |> put_status(:no_content)
      |> json(%{success: true})
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end
end
