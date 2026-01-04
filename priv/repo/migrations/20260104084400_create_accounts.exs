defmodule Micelio.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :email, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:handle])
    create unique_index(:accounts, [:email])
  end
end
