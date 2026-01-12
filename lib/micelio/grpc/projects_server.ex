defmodule Micelio.GRPC.Projects.V1.ProjectService.Server do
  use GRPC.Server, service: Micelio.GRPC.Projects.V1.ProjectService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Projects.V1

  alias Micelio.GRPC.Projects.V1.{
    CreateProjectRequest,
    DeleteProjectRequest,
    GetProjectRequest,
    ListProjectsRequest,
    ListProjectsResponse,
    UpdateProjectRequest
  }

  alias Micelio.Projects
  alias Micelio.Projects.Project

  def list_projects(%ListProjectsRequest{} = request, _stream) do
    with :ok <- require_field(request.user_id, "user_id"),
         :ok <- require_field(request.organization_handle, "organization_handle"),
         {:ok, user} <- fetch_user(request.user_id),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      projects = Projects.list_projects_for_organization(organization.id)

      %ListProjectsResponse{
        projects: Enum.map(projects, &project_to_proto(&1, organization))
      }
    else
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def get_project(%GetProjectRequest{} = request, _stream) do
    with :ok <- require_field(request.user_id, "user_id"),
         :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Project{} = project <- Projects.get_project_by_handle(organization.id, request.handle) do
      %V1.ProjectResponse{project: project_to_proto(project, organization)}
    else
      nil -> {:error, not_found_status("Project not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def create_project(%CreateProjectRequest{} = request, _stream) do
    with :ok <- require_field(request.user_id, "user_id"),
         :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         :ok <- require_field(request.name, "name"),
         {:ok, user} <- fetch_user(request.user_id),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id) do
      attrs = %{
        handle: request.handle,
        name: request.name,
        description: empty_to_nil(request.description),
        organization_id: organization.id
      }

      case Projects.create_project(attrs) do
        {:ok, project} ->
          %V1.ProjectResponse{project: project_to_proto(project, organization)}

        {:error, changeset} ->
          {:error, invalid_status("Invalid project: #{format_errors(changeset)}")}
      end
    else
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def update_project(%UpdateProjectRequest{} = request, _stream) do
    with :ok <- require_field(request.user_id, "user_id"),
         :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Project{} = project <- Projects.get_project_by_handle(organization.id, request.handle) do
      attrs = %{
        handle: empty_to_nil(request.new_handle) || project.handle,
        name: empty_to_nil(request.name) || project.name,
        description: empty_to_nil(request.description)
      }

      case Projects.update_project(project, attrs) do
        {:ok, updated} ->
          %V1.ProjectResponse{project: project_to_proto(updated, organization)}

        {:error, changeset} ->
          {:error, invalid_status("Invalid project: #{format_errors(changeset)}")}
      end
    else
      nil -> {:error, not_found_status("Project not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  def delete_project(%DeleteProjectRequest{} = request, _stream) do
    with :ok <- require_field(request.user_id, "user_id"),
         :ok <- require_field(request.organization_handle, "organization_handle"),
         :ok <- require_field(request.handle, "handle"),
         {:ok, user} <- fetch_user(request.user_id),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.organization_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         %Project{} = project <- Projects.get_project_by_handle(organization.id, request.handle),
         {:ok, _} <- Projects.delete_project(project) do
      %V1.DeleteProjectResponse{success: true}
    else
      nil -> {:error, not_found_status("Project not found.")}
      {:error, status} -> {:error, status}
      false -> {:error, forbidden_status("You do not have access to this organization.")}
    end
  end

  defp project_to_proto(project, organization) do
    organization_handle = organization.account.handle

    %V1.Project{
      id: project.id,
      organization_id: organization.id,
      organization_handle: organization_handle,
      handle: project.handle,
      name: project.name,
      description: project.description || "",
      inserted_at: format_timestamp(project.inserted_at),
      updated_at: format_timestamp(project.updated_at)
    }
  end

  defp fetch_user(nil), do: {:error, unauthenticated_status("User is required.")}

  defp fetch_user(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, unauthenticated_status("User not found.")}
      user -> {:ok, user}
    end
  end

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp format_timestamp(nil), do: ""

  defp format_timestamp(%DateTime{} = timestamp) do
    DateTime.to_iso8601(timestamp)
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field} #{Enum.join(errors, ", ")}"
    end)
  end

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
