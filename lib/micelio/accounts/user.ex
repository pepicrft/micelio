defmodule Micelio.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          email: String.t(),
          account_id: Ecto.UUID.t(),
          account: Micelio.Accounts.Account.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string

    belongs_to :account, Micelio.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new user.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :account_id])
    |> validate_required([:email])
    |> validate_email()
    |> unique_constraint(:email, name: :users_email_index)
    |> assoc_constraint(:account)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "must be a valid email address"
    )
    |> validate_length(:email, max: 160)
    |> update_change(:email, &String.downcase/1)
  end
end
