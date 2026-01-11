defmodule Micelio.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false
  alias Micelio.Repo
  alias Micelio.Sessions.Session
  alias Micelio.Projects.Project
  alias Micelio.Accounts.User

  @doc """
  Returns the list of sessions for a project.
  """
  def list_sessions_for_project(%Project{} = project) do
    Session
    |> where([s], s.project_id == ^project.id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a user.
  """
  def list_sessions_for_user(%User{} = user) do
    Session
    |> where([s], s.user_id == ^user.id)
    |> order_by([s], desc: s.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single session.
  """
  def get_session(id), do: Repo.get(Session, id)

  @doc """
  Gets a session by session_id.
  """
  def get_session_by_session_id(session_id) do
    Repo.get_by(Session, session_id: session_id)
  end

  @doc """
  Creates a session.
  """
  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lands a session (marks it as completed).
  """
  def land_session(%Session{} = session, attrs \\ %{}) do
    session
    |> Session.land_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a session.
  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a session.
  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end
end
