defmodule Micelio.Repo.Migrations.RenameLoginTokensToTokens do
  use Ecto.Migration

  def change do
    execute(
      "CREATE TYPE token_purpose AS ENUM ('login', 'email_verification', 'password_reset')",
      "DROP TYPE token_purpose"
    )

    rename table(:login_tokens), to: table(:tokens)

    alter table(:tokens) do
      add :purpose, :token_purpose, null: false, default: "login"
    end

    create index(:tokens, [:purpose])
  end
end
