defmodule Micelio.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    # Case-insensitive unique index on email (using lower())
    create unique_index(:users, ["lower(email)"], name: :users_email_index)
    create index(:users, [:account_id])
  end
end
