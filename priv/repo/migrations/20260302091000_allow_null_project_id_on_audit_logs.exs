defmodule Micelio.Repo.Migrations.AllowNullProjectIdOnAuditLogs do
  use Ecto.Migration

  def change do
    alter table(:audit_logs) do
      modify :project_id, :binary_id, null: true
    end
  end
end
