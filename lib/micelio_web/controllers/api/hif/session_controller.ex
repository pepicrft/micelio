defmodule MicelioWeb.API.Hif.SessionController do
  @moduledoc """
  API controller for hif sessions.
  """

  use MicelioWeb, :controller

  alias Micelio.Hif.Sessions

  action_fallback MicelioWeb.FallbackController

  @doc """
  Creates a new session.

  POST /api/hif/sessions
  Body: { "goal": "...", "project_id": "...", "user_id": "..." }
  """
  def create(conn, params) do
    with {:ok, session} <- Sessions.create_session(params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/hif/sessions/#{session.id}")
      |> render(:show, session: session)
    end
  end

  @doc """
  Gets a session by ID.

  GET /api/hif/sessions/:id
  """
  def show(conn, %{"id" => id}) do
    case Sessions.get_session(id) do
      nil -> {:error, :not_found}
      session -> render(conn, :show, session: session)
    end
  end

  @doc """
  Lists sessions for a project.

  GET /api/hif/sessions?project_id=...&state=...&user_id=...&limit=...
  """
  def index(conn, %{"project_id" => project_id} = params) do
    opts = build_list_opts(params)
    sessions = Sessions.list_sessions(project_id, opts)
    render(conn, :index, sessions: sessions)
  end

  def index(_conn, _params) do
    {:error, {:bad_request, "project_id is required"}}
  end

  @doc """
  Records a decision in the session.

  POST /api/hif/sessions/:id/decisions
  Body: { "text": "..." }
  """
  def add_decision(conn, %{"id" => id, "text" => text}) do
    with {:ok, session} <- load_session(id),
         {:ok, session} <- Sessions.record_decision(session, text) do
      render(conn, :show, session: session)
    end
  end

  @doc """
  Records a message in the session.

  POST /api/hif/sessions/:id/messages
  Body: { "role": "human|agent|system", "content": "..." }
  """
  def add_message(conn, %{"id" => id, "role" => role, "content" => content}) do
    with {:ok, session} <- load_session(id),
         {:ok, session} <- Sessions.record_message(session, role, content) do
      render(conn, :show, session: session)
    end
  end

  @doc """
  Records an operation in the session.

  POST /api/hif/sessions/:id/operations
  Body: { "type": "write|delete|rename|mkdir", "path": "...", ... }
  """
  def add_operation(conn, %{"id" => id, "type" => op_type, "path" => path} = params) do
    metadata = Map.drop(params, ["id", "type", "path"])

    with {:ok, session} <- load_session(id),
         {:ok, session} <- Sessions.record_operation(session, op_type, path, metadata) do
      render(conn, :show, session: session)
    end
  end

  @doc """
  Lands the session.

  POST /api/hif/sessions/:id/land
  """
  def land(conn, %{"id" => id}) do
    with {:ok, session} <- load_session(id),
         {:ok, session} <- Sessions.land_session(session) do
      render(conn, :show, session: session)
    end
  end

  @doc """
  Abandons the session.

  POST /api/hif/sessions/:id/abandon
  """
  def abandon(conn, %{"id" => id}) do
    with {:ok, session} <- load_session(id),
         {:ok, session} <- Sessions.abandon_session(session) do
      render(conn, :show, session: session)
    end
  end

  # Private helpers

  defp load_session(id) do
    case Sessions.get_session(id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp build_list_opts(params) do
    []
    |> maybe_add_opt(:state, params["state"])
    |> maybe_add_opt(:user_id, params["user_id"])
    |> maybe_add_opt(:limit, parse_int(params["limit"]))
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(int) when is_integer(int), do: int
end
