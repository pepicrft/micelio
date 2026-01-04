defmodule Micelio.Repo.Migrations.CreateRepositories do
  use Ecto.Migration

  def change do
    create table(:repositories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :description, :text

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:repositories, [:account_id])
    create unique_index(:repositories, [:account_id, :handle])
  end
end
