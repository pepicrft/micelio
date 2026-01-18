defmodule Micelio.Projects.ProjectStar do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_stars" do
    belongs_to :project, Micelio.Projects.Project
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for starring a project.
  """
  def changeset(project_star, attrs) do
    project_star
    |> cast(attrs, [:project_id, :user_id])
    |> validate_required([:project_id, :user_id])
    |> assoc_constraint(:project)
    |> assoc_constraint(:user)
    |> unique_constraint([:user_id, :project_id],
      name: :project_stars_user_id_project_id_index,
      message: "has already been starred"
    )
  end
end
