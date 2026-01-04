defmodule Micelio.Repo.Migrations.CreateHifSessions do
  use Ecto.Migration

  def change do
    create table(:hif_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :goal, :text, null: false
      add :state, :string, null: false, default: "active"
      add :decisions, {:array, :map}, null: false, default: []
      add :conversation, {:array, :map}, null: false, default: []
      add :operations, {:array, :map}, null: false, default: []
      add :landed_at, :utc_datetime_usec

      add :project_id, references(:repositories, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:hif_sessions, [:project_id])
    create index(:hif_sessions, [:user_id])
    create index(:hif_sessions, [:state])
    create index(:hif_sessions, [:project_id, :state])
  end
end
