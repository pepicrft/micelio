defmodule Micelio.AuditLog do
  use Micelio.Schema

  import Ecto.Changeset

  schema "audit_logs" do
    field :action, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Micelio.Projects.Project
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:project_id, :user_id, :action, :metadata])
    |> validate_required([:action])
  end

  def project_changeset(log, attrs) do
    log
    |> changeset(attrs)
    |> validate_required([:project_id])
  end

  def user_changeset(log, attrs) do
    log
    |> changeset(attrs)
    |> validate_required([:user_id])
  end
end
