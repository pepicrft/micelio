defmodule Micelio.Repositories.Repository do
  @moduledoc """
  Schema for repositories.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "repositories" do
    field :handle, :string
    field :description, :string

    belongs_to :account, Micelio.Accounts.Account
    has_many :hif_sessions, Micelio.Hif.Session, foreign_key: :project_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating/updating a repository.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:handle, :description, :account_id])
    |> validate_required([:handle, :account_id])
    |> validate_format(:handle, ~r/^[a-z0-9_-]+$/,
      message: "must be lowercase alphanumeric with underscores or dashes"
    )
    |> validate_length(:handle, min: 1, max: 100)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :handle])
  end
end
