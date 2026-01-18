defmodule Micelio.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:email, :string)

    has_one(:account, Micelio.Accounts.Account)
    has_many(:organization_memberships, Micelio.Accounts.OrganizationMembership)
    has_many(:organizations, through: [:organization_memberships, :organization])
    has_many(:project_stars, Micelio.Projects.ProjectStar)
    has_many(:starred_projects, through: [:project_stars, :project])
    has_many(:oauth_identities, Micelio.Accounts.OAuthIdentity)
    has_many(:passkeys, Micelio.Accounts.Passkey)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new user.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email()
    |> unique_constraint(:email, name: :users_email_index)
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
