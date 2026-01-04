defmodule Micelio.Accounts.Account do
  @moduledoc """
  Schema for user accounts.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field :handle, :string
    field :email, :string

    has_many :repositories, Micelio.Repositories.Repository
    has_many :hif_sessions, Micelio.Hif.Session, foreign_key: :user_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating/updating an account.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:handle, :email])
    |> validate_required([:handle, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_format(:handle, ~r/^[a-z0-9_]+$/,
      message: "must be lowercase alphanumeric with underscores"
    )
    |> validate_length(:handle, min: 1, max: 39)
    |> unique_constraint(:handle)
    |> unique_constraint(:email)
  end
end
