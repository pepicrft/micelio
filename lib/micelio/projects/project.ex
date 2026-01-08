defmodule Micelio.Projects.Project do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :handle, :string
    field :name, :string
    field :description, :string

    belongs_to :account, Micelio.Accounts.Account

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a project.
  """
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:handle, :name, :description, :account_id])
    |> validate_required([:handle, :name, :account_id])
    |> validate_handle()
    |> unique_constraint([:account_id, :handle],
      name: :projects_account_handle_index,
      message: "has already been taken for this account"
    )
    |> assoc_constraint(:account)
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:handle, ~r/^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,99}$/i,
      message:
        "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen"
    )
    |> validate_length(:handle, min: 1, max: 100)
  end
end
