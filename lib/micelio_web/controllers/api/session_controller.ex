defmodule MicelioWeb.API.SessionController do
  use MicelioWeb, :controller

  alias Micelio.{Accounts, Projects, Sessions, Storage}
  alias Micelio.OAuth.AccessTokens

  action_fallback MicelioWeb.API.FallbackController

  defp get_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

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
  Create a new session (land from CLI)
  POST /api/sessions
  Body: {
    "session_id": "abc123",
    "goal": "Add authentication",
    "organization": "myorg",
    "project": "myapp",
    "started_at": "timestamp",
    "conversation": [...],
    "decisions": [...],
    "files": [...] (optional)
  }
  """
  def create(conn, params) do
    with {:ok, user} <- authenticate(conn),
         {:ok, session_id} <- Map.fetch(params, "session_id"),
         {:ok, goal} <- Map.fetch(params, "goal"),
         {:ok, org_handle} <- Map.fetch(params, "organization"),
         {:ok, project_handle} <- Map.fetch(params, "project"),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, project_handle) do
      
      conversation = Map.get(params, "conversation", [])
      decisions = Map.get(params, "decisions", [])
      files = Map.get(params, "files", [])
      
      started_at = 
        case Map.get(params, "started_at") do
          nil -> DateTime.utc_now()
          timestamp when is_integer(timestamp) -> 
            DateTime.from_unix!(timestamp)
          timestamp when is_binary(timestamp) ->
            case Integer.parse(timestamp) do
              {unix_time, ""} -> DateTime.from_unix!(unix_time)
              _ -> DateTime.utc_now()
            end
          _ -> DateTime.utc_now()
        end

      # Create session in database
      session_attrs = %{
        session_id: session_id,
        goal: goal,
        project_id: project.id,
        user_id: user.id,
        conversation: conversation,
        decisions: decisions,
        started_at: started_at,
        metadata: %{
          organization_handle: org_handle,
          project_handle: project_handle,
          files_count: length(files)
        }
      }

      case Sessions.create_session(session_attrs) do
        {:ok, session} ->
          # Store files if provided
          if length(files) > 0 do
            store_session_files(session_id, files)
          end

          # Mark as landed
          {:ok, landed_session} = Sessions.land_session(session)

          conn
          |> put_status(:created)
          |> json(%{
            session: %{
              id: landed_session.id,
              session_id: landed_session.session_id,
              goal: landed_session.goal,
              project: "#{org_handle}/#{project_handle}",
              status: landed_session.status,
              conversation_count: length(conversation),
              decisions_count: length(decisions),
              files_count: length(files),
              started_at: landed_session.started_at,
              landed_at: landed_session.landed_at
            }
          })

        {:error, changeset} ->
          {:error, {:validation, changeset}}
      end
    else
      :error -> {:error, :bad_request}
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp store_session_files(session_id, files) do
    Enum.each(files, fn file ->
      path = Map.get(file, "path")
      content = Map.get(file, "content")
      
      if path && content do
        key = "sessions/#{session_id}/files/#{path}"
        Storage.put(key, content)
      end
    end)
  end
end
