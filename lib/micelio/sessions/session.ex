defmodule Micelio.Sessions.Session do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sessions" do
    field :session_id, :string
    field :goal, :string
    field :status, :string, default: "active"
    field :conversation, {:array, :map}, default: []
    field :decisions, {:array, :map}, default: []
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime
    field :landed_at, :utc_datetime

    belongs_to :project, Micelio.Projects.Project
    belongs_to :user, Micelio.Accounts.User
    has_many :changes, Micelio.Sessions.SessionChange

    timestamps()
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :session_id,
      :goal,
      :status,
      :project_id,
      :user_id,
      :conversation,
      :decisions,
      :metadata,
      :started_at,
      :landed_at
    ])
    |> validate_required([:session_id, :goal, :project_id, :user_id])
    |> validate_inclusion(:status, ["active", "landed", "abandoned"])
    |> unique_constraint(:session_id)
  end

  @doc false
  def create_changeset(session, attrs) do
    started_at =
      case attrs[:started_at] do
        nil -> DateTime.utc_now() |> DateTime.truncate(:second)
        dt -> dt
      end

    session
    |> changeset(attrs)
    |> put_change(:status, "active")
    |> put_change(:started_at, started_at)
  end

  @doc false
  def land_changeset(session, attrs \\ %{}) do
    session
    |> changeset(attrs)
    |> put_change(:status, "landed")
    |> put_change(:landed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc false
  def abandon_changeset(session) do
    session
    |> change()
    |> put_change(:status, "abandoned")
    |> put_change(:landed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
