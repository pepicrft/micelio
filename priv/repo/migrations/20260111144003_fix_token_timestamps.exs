defmodule Micelio.Repo.Migrations.FixTokenTimestamps do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE oauth_tokens ALTER COLUMN expires_at TYPE bigint USING EXTRACT(EPOCH FROM expires_at)::bigint"
    execute "ALTER TABLE oauth_tokens ALTER COLUMN revoked_at TYPE bigint USING EXTRACT(EPOCH FROM revoked_at)::bigint"
  end

  def down do
    execute "ALTER TABLE oauth_tokens ALTER COLUMN expires_at TYPE timestamp USING to_timestamp(expires_at)"
    execute "ALTER TABLE oauth_tokens ALTER COLUMN revoked_at TYPE timestamp USING to_timestamp(revoked_at)"
  end
end
