defmodule Micelio.Notifications do
  @moduledoc """
  Email notifications for repository activity.
  """

  require Logger

  alias Micelio.Accounts
  alias Micelio.Mailer
  alias Micelio.Notifications.ActivityEmail
  alias Micelio.Projects.Project
  alias Micelio.Repo
  alias Micelio.Sessions.Session

  @supervisor Micelio.Notifications.Supervisor

  @doc """
  Dispatches session landed notifications for a project.
  """
  def dispatch_session_landed(%Project{} = project, %Session{} = session, opts \\ []) do
    async = Keyword.get(opts, :async, default_async?())

    if async do
      case Task.Supervisor.start_child(@supervisor, fn ->
             deliver_session_landed(project, session)
           end) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("notification dispatch failed: #{inspect(reason)}")
          :error
      end
    else
      deliver_session_landed(project, session)
    end
  end

  @doc """
  Dispatches project starred notifications for a project.
  """
  def dispatch_project_starred(%Project{} = project, actor, opts \\ []) do
    async = Keyword.get(opts, :async, default_async?())

    if async do
      case Task.Supervisor.start_child(@supervisor, fn ->
             deliver_project_starred(project, actor)
           end) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("notification dispatch failed: #{inspect(reason)}")
          :error
      end
    else
      deliver_project_starred(project, actor)
    end
  end

  @doc """
  Delivers session landed emails to organization members.
  """
  def deliver_session_landed(%Project{} = project, %Session{} = session) do
    project = Repo.preload(project, organization: :account)
    session = Repo.preload(session, :user)

    recipients =
      project.organization_id
      |> Accounts.list_users_for_organization()
      |> Enum.filter(&valid_recipient?/1)

    emails =
      Enum.map(recipients, fn recipient ->
        ActivityEmail.session_landed_email(recipient, project, session)
      end)

    case emails do
      [] ->
        :ok

      _ ->
        case Mailer.deliver_many(emails) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Delivers project starred emails to organization members.
  """
  def deliver_project_starred(%Project{} = project, actor) do
    project = Repo.preload(project, organization: :account)

    recipients =
      project.organization_id
      |> Accounts.list_users_for_organization()
      |> Enum.filter(&valid_recipient?/1)

    emails =
      Enum.map(recipients, fn recipient ->
        ActivityEmail.project_starred_email(recipient, project, actor)
      end)

    case emails do
      [] ->
        :ok

      _ ->
        case Mailer.deliver_many(emails) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp valid_recipient?(user) do
    is_binary(user.email) and user.email != ""
  end

  defp default_async? do
    Application.get_env(:micelio, :notifications_async, true)
  end
end
