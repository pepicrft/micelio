defmodule Micelio.Accounts.Account do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          type: :user | :organization,
          handle: String.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :type, Ecto.Enum, values: [:user, :organization]
    field :handle, :string

    has_many :users, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new account.
  """
  def changeset(account, attrs) do
    account
    |> cast(attrs, [:type, :handle])
    |> validate_required([:type, :handle])
    |> validate_handle()
    |> unique_constraint(:handle, name: :accounts_handle_index)
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:handle, ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/i,
      message: "must start and end with alphanumeric characters, can contain hyphens"
    )
    |> validate_length(:handle, min: 2, max: 39)
    |> validate_exclusion(:handle, Micelio.Handles.reserved(), message: "is reserved")
  end
end
