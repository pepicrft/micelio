defmodule Micelio.Accounts.Organization do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organizations" do
    field :name, :string
    field :member_count, :integer, virtual: true

    has_one :account, Micelio.Accounts.Account
    has_many :memberships, Micelio.Accounts.OrganizationMembership
    has_many :users, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new organization.
  """
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
