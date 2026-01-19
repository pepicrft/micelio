defmodule Micelio.AuditLog do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

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
    |> validate_required([:project_id, :action])
  end
end
