defmodule Micelio.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    # Users/agents table
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :handle, :string, null: false
      add :email, :string
      add :password_hash, :string
      add :type, :string, null: false, default: "user"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:accounts, [:handle])
    create unique_index(:accounts, [:email], where: "email IS NOT NULL")
    create constraint(:accounts, :valid_type, check: "type IN ('user', 'agent')")

    # API tokens for hif CLI authentication
    create table(:api_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      add :name, :string, null: false
      add :scopes, {:array, :string}, default: []
      add :expires_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_tokens, [:token_hash])
    create index(:api_tokens, [:account_id])

    # Project permissions (who can access which hif projects)
    create table(:project_permissions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, :string, null: false
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "read"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_permissions, [:project_id, :account_id])
    create index(:project_permissions, [:account_id])
    create constraint(:project_permissions, :valid_role, check: "role IN ('owner', 'write', 'read')")
  end
end
