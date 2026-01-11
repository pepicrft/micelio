defmodule Micelio.Projects.Project do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :handle, :string
    field :name, :string
    field :description, :string

    belongs_to :organization, Micelio.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a project.
  """
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:handle, :name, :description])
    |> maybe_put_organization_id(attrs)
    |> validate_required([:handle, :name, :organization_id])
    |> validate_handle()
    |> unique_constraint(:handle,
      name: :projects_organization_handle_index,
      message: "has already been taken for this organization"
    )
    |> assoc_constraint(:organization)
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:handle, ~r/^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,99}$/i,
      message:
        "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen"
    )
    |> validate_length(:handle, min: 1, max: 100)
  end

  defp maybe_put_organization_id(changeset, attrs) do
    org_id = Map.get(attrs, :organization_id) || Map.get(attrs, "organization_id")

    if is_nil(org_id) do
      changeset
    else
      put_change(changeset, :organization_id, org_id)
    end
  end
end
