# Create test user for OAuth2 device flow testing
alias Micelio.Accounts
alias Micelio.Repo

# Create user
case Repo.insert(%Micelio.Accounts.User{email: "test@example.com"}) do
  {:ok, user} ->
    IO.puts("✅ Created test user: #{user.email}")

    # Create account for user
    case Accounts.create_user_account(%{
           handle: "testuser",
           user_id: user.id
         }) do
      {:ok, account} ->
        IO.puts("✅ Created account: #{account.handle}")

      {:error, changeset} ->
        IO.puts("❌ Failed to create account:")
        IO.inspect(changeset.errors)
    end

  {:error, %Ecto.Changeset{} = changeset} ->
    if Enum.any?(changeset.errors, fn {field, {msg, _}} ->
         field == :email and String.contains?(msg, "has already been taken")
       end) do
      IO.puts("ℹ️  Test user already exists")

      # Try to find and use existing user
      user = Repo.get_by(Micelio.Accounts.User, email: "test@example.com")

      if user && !Repo.preload(user, :account).account do
        case Accounts.create_user_account(%{
               handle: "testuser",
               user_id: user.id
             }) do
          {:ok, account} ->
            IO.puts("✅ Created account: #{account.handle}")

          {:error, changeset} ->
            IO.puts("ℹ️  Account might already exist or:")
            IO.inspect(changeset.errors)
        end
      else
        IO.puts("ℹ️  User and account already configured")
      end
    else
      IO.puts("❌ Failed to create test user:")
      IO.inspect(changeset.errors)
    end
end
