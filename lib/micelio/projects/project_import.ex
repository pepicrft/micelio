defmodule Micelio.Projects.ProjectImport do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["queued", "running", "completed", "failed", "rolled_back"]
  @stages ["metadata", "git_data_clone", "validation", "issue_migration", "finalization"]

  schema "project_imports" do
    field :source_url, :string
    field :source_forge, :string
    field :status, :string, default: "queued"
    field :stage, :string, default: "metadata"
    field :error_message, :string
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :project, Micelio.Projects.Project
    belongs_to :user, Micelio.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(import, attrs) do
    import
    |> cast(attrs, [
      :project_id,
      :user_id,
      :source_url,
      :source_forge,
      :status,
      :stage,
      :error_message,
      :metadata,
      :started_at,
      :completed_at
    ])
    |> validate_required([:project_id, :user_id, :source_url, :status, :stage])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:stage, @stages)
    |> validate_source_url()
    |> assoc_constraint(:project)
    |> assoc_constraint(:user)
  end

  def statuses, do: @statuses
  def stages, do: @stages

  defp validate_source_url(changeset) do
    validate_change(changeset, :source_url, fn :source_url, url ->
      if valid_source_url?(url) do
        []
      else
        [source_url: "must be a valid http(s) URL"]
      end
    end)
  end

  defp valid_source_url?(url) when is_binary(url) do
    url = String.trim(url)

    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      %URI{scheme: nil, path: path} ->
        allow_local_imports?() and is_binary(path) and path != ""

      _ ->
        false
    end
  end

  defp valid_source_url?(_), do: false

  defp allow_local_imports? do
    config = Application.get_env(:micelio, Micelio.Projects.Import, [])
    Keyword.get(config, :allow_local_imports, false)
  end
end
