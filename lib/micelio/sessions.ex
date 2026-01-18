defmodule Micelio.Sessions do
  @moduledoc """
  The Sessions context.
  """

  import Ecto.Query, warn: false

  alias Micelio.Accounts.User
  alias Micelio.Projects.Project
  alias Micelio.Repo
  alias Micelio.Sessions.Session
  alias Micelio.Sessions.SessionChange
  alias Micelio.Storage

  @doc """
  Returns the list of sessions for a project.
  """
  def list_sessions_for_project(%Project{} = project, opts \\ []) do
    project
    |> build_project_sessions_query(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a project with user and change details preloaded.
  """
  def list_sessions_for_project_with_details(%Project{} = project, opts \\ []) do
    project
    |> build_project_sessions_query(opts)
    |> preload([:changes, user: :account])
    |> Repo.all()
  end

  @doc """
  Counts sessions for a project, optionally filtered by status.
  """
  def count_sessions_for_project(%Project{} = project, opts \\ []) do
    status_filter = Keyword.get(opts, :status)

    query =
      Session
      |> where([s], s.project_id == ^project.id)

    query =
      if status_filter do
        where(query, [s], s.status == ^status_filter)
      else
        query
      end

    Repo.aggregate(query, :count)
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
  Gets a single session with preloaded associations.
  """
  def get_session_with_associations(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload([:user, :project])
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
  Abandons a session (marks it as abandoned).
  """
  def abandon_session(%Session{} = session) do
    session
    |> Session.abandon_changeset()
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

  ## Session Changes

  @doc """
  Gets a session with preloaded changes.
  """
  def get_session_with_changes(id) do
    Session
    |> Repo.get(id)
    |> Repo.preload([:user, :project, :changes])
  end

  @doc """
  Creates a session change.
  """
  def create_session_change(attrs \\ %{}) do
    %SessionChange{}
    |> SessionChange.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates multiple session changes in a transaction.
  """
  def create_session_changes(changes_list) when is_list(changes_list) do
    Repo.transaction(fn ->
      Enum.map(changes_list, fn attrs ->
        case create_session_change(attrs) do
          {:ok, change} -> change
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Lists all changes for a session.
  """
  def list_session_changes(%Session{} = session) do
    SessionChange
    |> where([c], c.session_id == ^session.id)
    |> order_by([c], asc: c.file_path)
    |> Repo.all()
  end

  @doc """
  Lists landed session changes for a file, ordered by landing time.
  """
  def list_landed_changes_for_file(project_id, file_path)
      when is_binary(project_id) and is_binary(file_path) do
    SessionChange
    |> join(:inner, [c], s in assoc(c, :session))
    |> where([c, s], s.project_id == ^project_id and s.status == "landed")
    |> where([c, _s], c.file_path == ^file_path)
    |> order_by([c, s], asc: s.landed_at, asc: c.inserted_at)
    |> preload([_c, s], session: [user: :account])
    |> Repo.all()
    |> Enum.map(fn change ->
      %{
        change_type: change.change_type,
        content: load_change_content(change),
        session: change.session
      }
    end)
  end

  @doc """
  Counts changes for a session, optionally by change type.
  """
  def count_session_changes(%Session{} = session, opts \\ []) do
    change_type = Keyword.get(opts, :change_type)

    query =
      SessionChange
      |> where([c], c.session_id == ^session.id)

    query =
      if change_type do
        where(query, [c], c.change_type == ^change_type)
      else
        query
      end

    Repo.aggregate(query, :count)
  end

  defp build_project_sessions_query(%Project{} = project, opts) do
    status_filter = Keyword.get(opts, :status)
    sort = Keyword.get(opts, :sort, :newest)

    query =
      Session
      |> where([s], s.project_id == ^project.id)

    query =
      if status_filter && status_filter != "all" do
        where(query, [s], s.status == ^status_filter)
      else
        query
      end

    case sort do
      :oldest -> order_by(query, asc: :started_at)
      :status -> order_by(query, asc: :status, desc: :started_at)
      _ -> order_by(query, desc: :started_at)
    end
  end

  defp load_change_content(%SessionChange{change_type: "deleted"}), do: nil

  defp load_change_content(%SessionChange{content: content}) when is_binary(content), do: content

  defp load_change_content(%SessionChange{storage_key: key}) when is_binary(key) do
    case Storage.get(key) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp load_change_content(_change), do: nil

  @doc """
  Gets statistics about session changes.
  """
  def get_session_change_stats(%Session{} = session) do
    %{
      total: count_session_changes(session),
      added: count_session_changes(session, change_type: "added"),
      modified: count_session_changes(session, change_type: "modified"),
      deleted: count_session_changes(session, change_type: "deleted")
    }
  end

  ## Activity/Contribution Data

  @doc """
  Returns activity counts grouped by date for a user.
  Counts landed sessions per day over the specified number of weeks.
  Returns a map of Date => count.
  """
  @spec activity_counts_for_user(User.t(), non_neg_integer()) :: %{Date.t() => non_neg_integer()}
  def activity_counts_for_user(%User{} = user, weeks \\ 52) do
    today = Date.utc_today()
    start_date = Date.add(today, -(weeks * 7))

    Session
    |> where([s], s.user_id == ^user.id)
    |> where([s], s.status == "landed")
    |> where([s], not is_nil(s.landed_at))
    |> where([s], s.landed_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"))
    |> select([s], s.landed_at)
    |> Repo.all()
    |> Enum.group_by(&DateTime.to_date/1)
    |> Map.new(fn {date, sessions} -> {date, length(sessions)} end)
  end

  @doc """
  Returns activity counts grouped by date for a user on public projects.
  Counts landed sessions per day over the specified number of weeks.
  Returns a map of Date => count.
  """
  @spec activity_counts_for_user_public(User.t(), non_neg_integer()) ::
          %{Date.t() => non_neg_integer()}
  def activity_counts_for_user_public(%User{} = user, weeks \\ 52) do
    today = Date.utc_today()
    start_date = Date.add(today, -(weeks * 7))

    Session
    |> join(:inner, [s], p in assoc(s, :project))
    |> where([s, _p], s.user_id == ^user.id)
    |> where([s, _p], s.status == "landed")
    |> where([s, _p], not is_nil(s.landed_at))
    |> where([s, _p], s.landed_at >= ^DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"))
    |> where([_s, p], p.visibility == "public")
    |> select([s, _p], s.landed_at)
    |> Repo.all()
    |> Enum.group_by(&DateTime.to_date/1)
    |> Map.new(fn {date, sessions} -> {date, length(sessions)} end)
  end
end
