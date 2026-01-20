defmodule Micelio.Accounts.OAuthIdentity do
  use Micelio.Schema

  import Ecto.Changeset

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
