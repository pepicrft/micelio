defmodule MicelioWeb.API.SessionController do
  use MicelioWeb, :controller

  alias Micelio.OAuth.AccessTokens
  alias Micelio.Sessions.{Conflict, Session}
  alias Micelio.{Accounts, Projects, Projects.Project, Sessions, Storage}

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

      started_at = parse_timestamp(Map.get(params, "started_at"))

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
          project_handle: project_handle
        }
      }

      case Sessions.create_session(session_attrs) do
        {:ok, session} ->
          # Store files and create session changes
          change_stats =
            if not Enum.empty?(files) do
              store_session_changes(session, files)
            else
              %{total: 0, added: 0, modified: 0, deleted: 0}
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
              changes: change_stats,
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

  @doc """
  Starts a new session without landing it.
  """
  def start(conn, params) do
    with {:ok, user} <- authenticate(conn),
         {:ok, session_id} <- Map.fetch(params, "session_id"),
         {:ok, goal} <- Map.fetch(params, "goal"),
         {:ok, org_handle} <- Map.fetch(params, "organization"),
         {:ok, project_handle} <- Map.fetch(params, "project"),
         {:ok, organization} <- Accounts.get_organization_by_handle(org_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, project_handle),
         nil <- Sessions.get_session_by_session_id(session_id) do
      conversation = Map.get(params, "conversation", [])
      decisions = Map.get(params, "decisions", [])

      session_attrs = %{
        session_id: session_id,
        goal: goal,
        project_id: project.id,
        user_id: user.id,
        conversation: conversation,
        decisions: decisions,
        started_at: parse_timestamp(Map.get(params, "started_at")),
        metadata: %{
          organization_handle: org_handle,
          project_handle: project_handle
        }
      }

      case Sessions.create_session(session_attrs) do
        {:ok, session} ->
          conn
          |> put_status(:created)
          |> json(%{
            session: %{
              id: session.id,
              session_id: session.session_id,
              goal: session.goal,
              project: "#{org_handle}/#{project_handle}",
              status: session.status,
              conversation_count: length(conversation),
              decisions_count: length(decisions),
              started_at: session.started_at
            }
          })

        {:error, changeset} ->
          {:error, {:validation, changeset}}
      end
    else
      %Session{} -> {:error, :conflict}
      :error -> {:error, :bad_request}
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      error -> error
    end
  end

  @doc """
  Lands an active session and stores its changes.
  """
  def land(conn, %{"session_id" => session_id} = params) do
    with {:ok, user} <- authenticate(conn),
         %Session{} = session <- Sessions.get_session_by_session_id(session_id),
         %Project{} = project <- Projects.get_project_with_organization(session.project_id),
         true <- Accounts.user_in_organization?(user, project.organization.id),
         true <- session.status == "active" do
      conversation = Map.get(params, "conversation", session.conversation)
      decisions = Map.get(params, "decisions", session.decisions)
      files = Map.get(params, "files", [])

      metadata_updates = Map.get(params, "metadata", %{})

      {:ok, updated_session} =
        Sessions.update_session(session, %{
          conversation: conversation,
          decisions: decisions,
          metadata: Map.merge(session.metadata || %{}, metadata_updates)
        })

      change_stats =
        if not Enum.empty?(files) do
          store_session_changes(updated_session, files)
        else
          %{total: 0, added: 0, modified: 0, deleted: 0}
        end

      {:ok, landed_session} = Sessions.land_session(updated_session)

      conn
      |> put_status(:ok)
      |> json(%{
        session: %{
          id: landed_session.id,
          session_id: landed_session.session_id,
          goal: landed_session.goal,
          project: "#{project.organization.handle}/#{project.handle}",
          status: landed_session.status,
          conversation_count: length(conversation),
          decisions_count: length(decisions),
          changes: change_stats,
          started_at: landed_session.started_at,
          landed_at: landed_session.landed_at
        }
      })
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      _ -> {:error, :conflict}
    end
  end

  defp store_session_changes(session, files) do
    # Track changes by type
    stats = %{total: 0, added: 0, modified: 0, deleted: 0}

    changes_attrs =
      Enum.map(files, fn file ->
        path = Map.get(file, "path")
        content = Map.get(file, "content")
        # Default to modified
        change_type = Map.get(file, "change_type", "modified")

        # For large files, store in S3/local storage and reference by key
        # For small files (< 100KB), store inline
        {storage_key, inline_content} =
          if content && byte_size(content) > 100_000 do
            key = "sessions/#{session.session_id}/changes/#{path}"
            {:ok, _} = Storage.put(key, content)
            {key, nil}
          else
            {nil, content}
          end

      %{
        session_id: session.id,
        file_path: path,
        change_type: change_type,
        storage_key: storage_key,
          content: inline_content,
          metadata: %{
            size: if(content, do: byte_size(content), else: 0)
          }
        }
      end)

    # Create all changes in a transaction
    case Sessions.create_session_changes(changes_attrs) do
      {:ok, changes} ->
        filter =
          changes
          |> Enum.map(& &1.file_path)
          |> Conflict.build_filter()

        _ =
          Sessions.update_session(session, %{
            metadata: Map.merge(session.metadata || %{}, %{"change_filter" => filter})
          })

        # Calculate stats
        Enum.reduce(changes, stats, fn change, acc ->
          acc
          |> Map.update!(:total, &(&1 + 1))
          |> Map.update!(String.to_atom(change.change_type), &(&1 + 1))
        end)

      {:error, _} ->
        stats
    end
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
  end

  defp parse_timestamp(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {unix_time, ""} -> DateTime.from_unix!(unix_time)
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end
