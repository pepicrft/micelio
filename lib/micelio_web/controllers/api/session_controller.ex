defmodule MicelioWeb.API.SessionController do
  use MicelioWeb, :controller

  alias Micelio.{Accounts, Projects}
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
    "decisions": [...]
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
      # For now, just log the session (no database storage yet)
      # This will be expanded to actually store sessions
      IO.puts("Session landed:")
      IO.puts("  ID: #{session_id}")
      IO.puts("  Goal: #{goal}")
      IO.puts("  Project: #{org_handle}/#{project_handle}")
      IO.puts("  User: #{user.email}")

      conversation = Map.get(params, "conversation", [])
      decisions = Map.get(params, "decisions", [])

      IO.puts("  Conversation: #{length(conversation)} messages")
      IO.puts("  Decisions: #{length(decisions)} decisions")

      # TODO: Store in database, create session record, handle file changes
      # For now, return success

      conn
      |> put_status(:created)
      |> json(%{
        session: %{
          id: session_id,
          goal: goal,
          project: "#{org_handle}/#{project_handle}",
          status: "landed",
          message: "Session received (storage not yet implemented)"
        }
      })
    else
      :error -> {:error, :bad_request}
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end
end
