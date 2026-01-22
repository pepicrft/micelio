defmodule Micelio.Audit do
  @moduledoc """
  Audit logging for project operations.
  """

  import Ecto.Query

  alias Micelio.Accounts.User
  alias Micelio.AuditLog
  alias Micelio.Projects.Project
  alias Micelio.Repo

  def log_project_action(%Project{} = project, action, opts \\ []) when is_binary(action) do
    user = Keyword.get(opts, :user)
    metadata = Keyword.get(opts, :metadata, %{})

    attrs =
      %{
        project_id: project.id,
        action: action,
        metadata: metadata
      }
      |> maybe_put_user_id(user)

    %AuditLog{}
    |> AuditLog.project_changeset(attrs)
    |> Repo.insert()
  end

  def log_user_action(%User{} = user, action, opts \\ []) when is_binary(action) do
    metadata = Keyword.get(opts, :metadata, %{})

    attrs = %{
      user_id: user.id,
      action: action,
      metadata: metadata
    }

    %AuditLog{}
    |> AuditLog.user_changeset(attrs)
    |> Repo.insert()
  end

  def list_project_logs(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> where([log], log.project_id == ^project_id)
    |> order_by([log], desc: log.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_put_user_id(attrs, %User{} = user), do: Map.put(attrs, :user_id, user.id)
  defp maybe_put_user_id(attrs, _), do: attrs
end
