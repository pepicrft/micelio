defmodule Micelio.Accounts.LoginToken do
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          token: String.t(),
          user_id: Ecto.UUID.t(),
          user: Micelio.Accounts.User.t() | Ecto.Association.NotLoaded.t(),
          expires_at: DateTime.t(),
          used_at: DateTime.t() | nil,
          inserted_at: DateTime.t()
        }

  @token_validity_minutes 15

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "login_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Creates a changeset for a new login token.
  Automatically generates a secure token and sets expiration.
  """
  def changeset(login_token, attrs) do
    login_token
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> put_token()
    |> put_expiration()
    |> assoc_constraint(:user)
  end

  @doc """
  Marks a token as used.
  """
  def use_changeset(login_token) do
    login_token
    |> change(used_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Returns true if the token is valid (not expired and not used).
  """
  def valid?(%__MODULE__{expires_at: expires_at, used_at: used_at}) do
    is_nil(used_at) && DateTime.before?(DateTime.utc_now(), expires_at)
  end

  def valid?(_), do: false

  defp put_token(changeset) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    put_change(changeset, :token, token)
  end

  defp put_expiration(changeset) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@token_validity_minutes, :minute)
      |> DateTime.truncate(:second)

    put_change(changeset, :expires_at, expires_at)
  end
end
