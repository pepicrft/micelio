defmodule Micelio.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    # Account types enum
    execute(
      "CREATE TYPE account_type AS ENUM ('user', 'organization')",
      "DROP TYPE account_type"
    )

    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :account_type, null: false
      add :handle, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Case-insensitive unique index on handle (using lower())
    create unique_index(:accounts, ["lower(handle)"], name: :accounts_handle_index)
  end
end
