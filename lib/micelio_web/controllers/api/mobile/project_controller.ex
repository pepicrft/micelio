defmodule MicelioWeb.Api.Mobile.ProjectController do
  use MicelioWeb, :controller

  alias Micelio.Projects

  @default_limit 20
  @min_limit 1
  @max_limit 50

  def index(conn, params) do
    with {:ok, limit} <- parse_limit(params["limit"]),
         {:ok, offset} <- parse_offset(params["offset"]),
         {:ok, updated_since} <- parse_updated_since(params["updated_since"]) do
      fetch_limit = limit + 1

      projects =
        Projects.list_mobile_projects(
          user: conn.assigns[:current_user],
          limit: fetch_limit,
          offset: offset,
          updated_since: updated_since
        )

      {page_projects, next_offset} = paginate_results(projects, limit, offset)

      conn
      |> json(%{
        data: Enum.map(page_projects, &project_payload/1),
        pagination: %{
          limit: limit,
          offset: offset,
          next_offset: next_offset
        },
        sync: %{
          latest_updated_at: latest_updated_at(page_projects)
        }
      })
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  def show(conn, %{
        "organization_handle" => organization_handle,
        "project_handle" => project_handle
      }) do
    case Projects.get_project_for_user_by_handle_with_star_count(
           conn.assigns[:current_user],
           organization_handle,
           project_handle
         ) do
      {:ok, project, organization} ->
        conn
        |> json(%{data: project_payload(project, organization)})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Project not found"})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Project is private"})
    end
  end

  defp project_payload(%{organization: organization} = project) do
    project_payload(project, organization)
  end

  defp project_payload(project, organization) do
    %{
      id: project.id,
      name: project.name,
      handle: project.handle,
      description: project.description,
      visibility: project.visibility,
      star_count: project.star_count || 0,
      updated_at: format_datetime(project.updated_at),
      organization: %{
        id: organization.id,
        handle: organization.account.handle,
        name: organization.name
      }
    }
  end

  defp paginate_results(projects, limit, offset) do
    if length(projects) > limit do
      {Enum.take(projects, limit), offset + limit}
    else
      {projects, nil}
    end
  end

  defp latest_updated_at([]), do: nil

  defp latest_updated_at(projects) do
    projects
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      timestamps ->
        timestamps
        |> Enum.max_by(&DateTime.to_unix/1)
        |> format_datetime()
    end
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp parse_limit(nil), do: {:ok, @default_limit}

  defp parse_limit(value) do
    parse_integer(value, @min_limit, @max_limit, "limit")
  end

  defp parse_offset(nil), do: {:ok, 0}

  defp parse_offset(value) do
    parse_integer(value, 0, 100_000, "offset")
  end

  defp parse_integer(value, min, max, label) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} when parsed >= min and parsed <= max ->
        {:ok, parsed}

      _ ->
        {:error, "#{label} must be between #{min} and #{max}"}
    end
  end

  defp parse_updated_since(nil), do: {:ok, nil}
  defp parse_updated_since(""), do: {:ok, nil}

  defp parse_updated_since(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> {:error, "updated_since must be ISO8601"}
    end
  end
end
