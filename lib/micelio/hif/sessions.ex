defmodule Micelio.Hif.Sessions do
  @moduledoc """
  Context module for managing hif sessions.

  Sessions are the core unit of work in hif. They capture not just
  what changed, but why - the goal, decisions, and conversation that
  led to those changes.
  """

  import Ecto.Query

  alias Micelio.Hif.Session
  alias Micelio.Repo

  @type session_attrs :: %{
          goal: String.t(),
          project_id: String.t(),
          user_id: String.t()
        }

  @doc """
  Creates a new session with the given goal.

  ## Examples

      iex> create_session(%{goal: "Add auth", project_id: id, user_id: uid})
      {:ok, %Session{}}

      iex> create_session(%{goal: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_session(session_attrs()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(attrs) do
    %Session{}
    |> Session.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a session by ID.

  Returns nil if the session doesn't exist.
  """
  @spec get_session(String.t()) :: Session.t() | nil
  def get_session(id) do
    Repo.get(Session, id)
  end

  @doc """
  Gets a session by ID, raising if not found.
  """
  @spec get_session!(String.t()) :: Session.t()
  def get_session!(id) do
    Repo.get!(Session, id)
  end

  @doc """
  Gets the active session for a user in a project.

  A user can only have one active session per project at a time.
  """
  @spec get_active_session(String.t(), String.t()) :: Session.t() | nil
  def get_active_session(project_id, user_id) do
    Session
    |> where([s], s.project_id == ^project_id)
    |> where([s], s.user_id == ^user_id)
    |> where([s], s.state == "active")
    |> Repo.one()
  end

  @doc """
  Lists all sessions for a project.

  Options:
  - :state - filter by state
  - :user_id - filter by user
  - :limit - max results (default 100)
  """
  @spec list_sessions(String.t(), keyword()) :: [Session.t()]
  def list_sessions(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Session
    |> where([s], s.project_id == ^project_id)
    |> maybe_filter_state(opts[:state])
    |> maybe_filter_user(opts[:user_id])
    |> order_by([s], desc: s.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Records a decision in the session.

  Decisions capture the "why" behind changes.
  """
  @spec record_decision(Session.t(), String.t()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def record_decision(%Session{state: "active"} = session, text) do
    decision = %{
      "text" => text,
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    session
    |> Session.decision_changeset(decision)
    |> Repo.update()
  end

  def record_decision(%Session{state: state}, _text) do
    {:error, {:invalid_state, "cannot record decision in #{state} session"}}
  end

  @doc """
  Records a conversation message in the session.

  Messages have a role (human, agent, system) and content.
  """
  @spec record_message(Session.t(), String.t(), String.t()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def record_message(%Session{state: "active"} = session, role, content)
      when role in ["human", "agent", "system"] do
    message = %{
      "role" => role,
      "content" => content,
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    session
    |> Session.conversation_changeset(message)
    |> Repo.update()
  end

  def record_message(%Session{state: state}, _role, _content) do
    {:error, {:invalid_state, "cannot record message in #{state} session"}}
  end

  @doc """
  Records a file operation in the session.

  Operations are: write, delete, rename, mkdir
  """
  @spec record_operation(Session.t(), String.t(), String.t(), map()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def record_operation(session, op_type, path, metadata \\ %{})

  def record_operation(%Session{state: "active"} = session, op_type, path, metadata)
      when op_type in ["write", "delete", "rename", "mkdir"] do
    operation =
      Map.merge(metadata, %{
        "type" => op_type,
        "path" => path,
        "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    session
    |> Session.operation_changeset(operation)
    |> Repo.update()
  end

  def record_operation(%Session{state: state}, _op_type, _path, _metadata) do
    {:error, {:invalid_state, "cannot record operation in #{state} session"}}
  end

  @doc """
  Lands the session, finalizing all changes.

  This transitions the session to "landed" state and records
  the landing timestamp.
  """
  @spec land_session(Session.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t() | tuple()}
  def land_session(%Session{state: "active"} = session) do
    session
    |> Session.state_changeset(%{state: "landed", landed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def land_session(%Session{state: state}) do
    {:error, {:invalid_state, "cannot land session in #{state} state"}}
  end

  @doc """
  Abandons the session, discarding all changes.
  """
  @spec abandon_session(Session.t()) ::
          {:ok, Session.t()} | {:error, Ecto.Changeset.t() | tuple()}
  def abandon_session(%Session{state: state} = session) when state in ["active", "conflicted"] do
    session
    |> Session.state_changeset(%{state: "abandoned"})
    |> Repo.update()
  end

  def abandon_session(%Session{state: state}) do
    {:error, {:invalid_state, "cannot abandon session in #{state} state"}}
  end

  # Private helpers

  defp maybe_filter_state(query, nil), do: query
  defp maybe_filter_state(query, state), do: where(query, [s], s.state == ^state)

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [s], s.user_id == ^user_id)
end
