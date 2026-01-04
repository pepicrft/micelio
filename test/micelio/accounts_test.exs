defmodule Micelio.AccountsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Accounts.{Account, User, LoginToken}

  describe "accounts" do
    test "create_account/1 with valid data creates an account" do
      assert {:ok, %Account{} = account} =
               Accounts.create_account(%{type: :user, handle: "testuser"})

      assert account.type == :user
      assert account.handle == "testuser"
    end

    test "create_account/1 with organization type" do
      assert {:ok, %Account{} = account} =
               Accounts.create_account(%{type: :organization, handle: "my-org"})

      assert account.type == :organization
      assert account.handle == "my-org"
    end

    test "create_account/1 with invalid handle fails" do
      assert {:error, changeset} = Accounts.create_account(%{type: :user, handle: "-invalid"})

      assert "must start and end with alphanumeric characters, can contain hyphens" in errors_on(
               changeset
             ).handle
    end

    test "create_account/1 with reserved handle fails" do
      assert {:error, changeset} = Accounts.create_account(%{type: :user, handle: "admin"})
      assert "is reserved" in errors_on(changeset).handle
    end

    test "create_account/1 with duplicate handle fails" do
      assert {:ok, _} = Accounts.create_account(%{type: :user, handle: "unique"})
      assert {:error, changeset} = Accounts.create_account(%{type: :user, handle: "unique"})
      assert "has already been taken" in errors_on(changeset).handle
    end

    test "create_account/1 handle is case-insensitive" do
      assert {:ok, _} = Accounts.create_account(%{type: :user, handle: "CamelCase"})
      assert {:error, changeset} = Accounts.create_account(%{type: :user, handle: "camelcase"})
      assert "has already been taken" in errors_on(changeset).handle
    end

    test "get_account/1 returns the account" do
      {:ok, account} = Accounts.create_account(%{type: :user, handle: "findme"})
      assert Accounts.get_account(account.id) == account
    end

    test "get_account_by_handle/1 returns the account" do
      {:ok, account} = Accounts.create_account(%{type: :user, handle: "byhandle"})
      assert Accounts.get_account_by_handle("byhandle") == account
    end

    test "get_account_by_handle/1 is case-insensitive" do
      {:ok, account} = Accounts.create_account(%{type: :user, handle: "MixedCase"})
      assert Accounts.get_account_by_handle("mixedcase").id == account.id
    end

    test "handle_available?/1 returns true for available handles" do
      assert Accounts.handle_available?("available-handle")
    end

    test "handle_available?/1 returns false for reserved handles" do
      refute Accounts.handle_available?("admin")
      refute Accounts.handle_available?("settings")
    end

    test "handle_available?/1 returns false for taken handles" do
      {:ok, _} = Accounts.create_account(%{type: :user, handle: "taken"})
      refute Accounts.handle_available?("taken")
    end

    test "create_organization/1 creates an organization account" do
      assert {:ok, %Account{} = account} = Accounts.create_organization(%{handle: "my-company"})
      assert account.type == :organization
      assert account.handle == "my-company"
    end
  end

  describe "users" do
    test "get_or_create_user_by_email/1 creates a new user with account" do
      assert {:ok, %User{} = user} = Accounts.get_or_create_user_by_email("new@example.com")
      assert user.email == "new@example.com"
      assert user.account != nil
      assert user.account.type == :user
    end

    test "get_or_create_user_by_email/1 returns existing user" do
      {:ok, user1} = Accounts.get_or_create_user_by_email("existing@example.com")
      {:ok, user2} = Accounts.get_or_create_user_by_email("existing@example.com")
      assert user1.id == user2.id
    end

    test "get_or_create_user_by_email/1 normalizes email to lowercase" do
      {:ok, user} = Accounts.get_or_create_user_by_email("UPPER@EXAMPLE.COM")
      assert user.email == "upper@example.com"
    end

    test "get_or_create_user_by_email/1 generates handle from email" do
      {:ok, user} = Accounts.get_or_create_user_by_email("john.doe@example.com")
      assert user.account.handle == "john-doe"
    end

    test "get_or_create_user_by_email/1 generates unique handle if taken" do
      {:ok, _} = Accounts.create_account(%{type: :user, handle: "john"})
      {:ok, user} = Accounts.get_or_create_user_by_email("john@example.com")
      assert user.account.handle == "john-1"
    end

    test "get_user/1 returns the user" do
      {:ok, user} = Accounts.get_or_create_user_by_email("getuser@example.com")
      assert Accounts.get_user(user.id).id == user.id
    end

    test "get_user_by_email/1 returns the user" do
      {:ok, user} = Accounts.get_or_create_user_by_email("byemail@example.com")
      assert Accounts.get_user_by_email("byemail@example.com").id == user.id
    end

    test "get_user_with_account/1 preloads account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("withaccount@example.com")
      loaded = Accounts.get_user_with_account(user.id)
      assert loaded.account.handle != nil
    end
  end

  describe "authentication" do
    test "initiate_login/1 creates a login token" do
      assert {:ok, %LoginToken{} = token} = Accounts.initiate_login("login@example.com")
      assert token.token != nil
      assert token.expires_at != nil
      assert token.used_at == nil
    end

    test "initiate_login/1 creates user if not exists" do
      assert {:ok, %LoginToken{}} = Accounts.initiate_login("newlogin@example.com")
      assert Accounts.get_user_by_email("newlogin@example.com") != nil
    end

    test "verify_login_token/1 returns user for valid token" do
      {:ok, token} = Accounts.initiate_login("verify@example.com")
      assert {:ok, user} = Accounts.verify_login_token(token.token)
      assert user.email == "verify@example.com"
      assert user.account != nil
    end

    test "verify_login_token/1 marks token as used" do
      {:ok, token} = Accounts.initiate_login("markused@example.com")
      {:ok, _} = Accounts.verify_login_token(token.token)

      # Token should be marked as used
      updated_token = Repo.get!(LoginToken, token.id)
      assert updated_token.used_at != nil
    end

    test "verify_login_token/1 fails for already used token" do
      {:ok, token} = Accounts.initiate_login("usedtoken@example.com")
      {:ok, _} = Accounts.verify_login_token(token.token)

      # Second attempt should fail
      assert {:error, :invalid_token} = Accounts.verify_login_token(token.token)
    end

    test "verify_login_token/1 fails for invalid token" do
      assert {:error, :invalid_token} = Accounts.verify_login_token("invalid-token")
    end

    test "verify_login_token/1 fails for expired token" do
      {:ok, token} = Accounts.initiate_login("expired@example.com")

      # Manually expire the token
      Repo.update!(Ecto.Changeset.change(token, expires_at: ~U[2020-01-01 00:00:00Z]))

      assert {:error, :invalid_token} = Accounts.verify_login_token(token.token)
    end

    test "LoginToken.valid?/1 returns true for valid token" do
      {:ok, token} = Accounts.initiate_login("validcheck@example.com")
      assert LoginToken.valid?(token)
    end

    test "LoginToken.valid?/1 returns false for used token" do
      {:ok, token} = Accounts.initiate_login("usedcheck@example.com")
      used_token = %{token | used_at: DateTime.utc_now()}
      refute LoginToken.valid?(used_token)
    end

    test "LoginToken.valid?/1 returns false for expired token" do
      {:ok, token} = Accounts.initiate_login("expiredcheck@example.com")
      expired_token = %{token | expires_at: ~U[2020-01-01 00:00:00Z]}
      refute LoginToken.valid?(expired_token)
    end
  end
end
