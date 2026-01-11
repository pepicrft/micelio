defmodule Micelio.Repo.Migrations.FixAuthorizationDetailsType do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE oauth_tokens ALTER COLUMN authorization_details TYPE jsonb USING authorization_details::jsonb"
  end

  def down do
    execute "ALTER TABLE oauth_tokens ALTER COLUMN authorization_details TYPE text"
  end
end
