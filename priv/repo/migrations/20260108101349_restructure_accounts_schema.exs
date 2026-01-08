defmodule Micelio.Repo.Migrations.RestructureAccountsSchema do
  use Ecto.Migration

  def change do
    # Create organizations table
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # Remove the account_id foreign key from users
    drop constraint(:users, "users_account_id_fkey")
    alter table(:users) do
      remove :account_id
    end

    # Restructure accounts table
    execute("DROP TYPE IF EXISTS account_type CASCADE", "")

    alter table(:accounts) do
      remove :type

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)
    end

    create index(:accounts, [:user_id])
    create index(:accounts, [:organization_id])

    # Add constraint to ensure account belongs to either user or org, not both
    create constraint(:accounts, :account_owner_exclusive,
             check: "(user_id IS NOT NULL AND organization_id IS NULL) OR (user_id IS NULL AND organization_id IS NOT NULL)"
           )
  end
end
