defmodule Micelio.Accounts.OAuthIdentity do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "oauth_identities" do
    field :provider, :string
    field :provider_user_id, :string

    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :provider_user_id, :user_id])
    |> validate_required([:provider, :provider_user_id, :user_id])
    |> unique_constraint(:provider_user_id,
      name: :oauth_identities_provider_provider_user_id_index
    )
  end
end
