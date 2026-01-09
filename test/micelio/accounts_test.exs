defmodule Micelio.AccountsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Accounts.{Account, Organization, User, Token}

  describe "Account user_changeset" do
    setup do
      {:ok, user} = Repo.insert(%User{email: "changeset-test@example.com"})
      {:ok, user: user}
    end

    test "validates required fields", %{user: _user} do
      changeset = Account.user_changeset(%Account{}, %{})
      assert "can't be blank" in errors_on(changeset).handle
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "validates single character handle is valid", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "a"})
      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle maximum length", %{user: user} do
      long_handle = String.duplicate("a", 40)
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: long_handle})
      assert "should be at most 39 character(s)" in errors_on(changeset).handle
    end

    test "validates handle format - no special characters", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test_user"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - can contain hyphens in middle", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test-user"})
      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle format - cannot end with hyphen", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "testuser-"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot have consecutive hyphens", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test--user"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot start with hyphen", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "-testuser"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end
  end

  describe "User changeset" do
    test "validates required email" do
      changeset = User.changeset(%User{}, %{})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "validates email format" do
      changeset = User.changeset(%User{}, %{email: "invalid"})
      assert "must be a valid email address" in errors_on(changeset).email
    end

    test "validates email max length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.changeset(%User{}, %{email: long_email})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "normalizes email to lowercase" do
      changeset = User.changeset(%User{}, %{email: "TEST@EXAMPLE.COM"})
      assert Ecto.Changeset.get_change(changeset, :email) == "test@example.com"
    end
  end

  describe "Token changeset" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("token-test@example.com")
      {:ok, user: user}
    end

    test "validates required fields", %{user: _user} do
      changeset = Token.changeset(%Token{}, %{})
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).purpose
    end

    test "automatically generates token", %{user: user} do
      changeset = Token.changeset(%Token{}, %{user_id: user.id, purpose: :login})
      assert Ecto.Changeset.get_change(changeset, :token) != nil
    end

    test "automatically sets expiration", %{user: user} do
      changeset = Token.changeset(%Token{}, %{user_id: user.id, purpose: :login})
      expires_at = Ecto.Changeset.get_change(changeset, :expires_at)
      assert expires_at != nil
      assert DateTime.after?(expires_at, DateTime.utc_now())
    end
  end

  describe "accounts" do
    test "get_account/1 returns the account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("findme@example.com")
      assert Accounts.get_account(user.account.id).id == user.account.id
    end

    test "get_account_by_handle/1 returns the account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("byhandle@example.com")
      assert Accounts.get_account_by_handle(user.account.handle).id == user.account.id
    end

    test "get_account_by_handle/1 is case-insensitive" do
      {:ok, user} = Accounts.get_or_create_user_by_email("mixedcase@example.com")
      handle = user.account.handle
      assert Accounts.get_account_by_handle(String.upcase(handle)).id == user.account.id
    end

    test "handle_available?/1 returns true for available handles" do
      assert Accounts.handle_available?("available-handle")
    end

    test "handle_available?/1 returns false for reserved handles" do
      refute Accounts.handle_available?("admin")
      refute Accounts.handle_available?("settings")
      refute Accounts.handle_available?("pedro")
      refute Accounts.handle_available?("micelio")
    end

    test "handle_available?/1 returns false for taken handles" do
      {:ok, user} = Accounts.get_or_create_user_by_email("taken@example.com")
      refute Accounts.handle_available?(user.account.handle)
    end

    test "create_organization/1 creates an organization with account" do
      assert {:ok, %Organization{} = org} =
               Accounts.create_organization(%{handle: "my-company", name: "My Company"})

      assert org.name == "My Company"
      assert org.account.handle == "my-company"
      assert Account.organization?(org.account)
    end

    test "create_organization/1 fails when handle is taken" do
      assert {:ok, %Organization{}} =
               Accounts.create_organization(%{handle: "taken-org", name: "Taken Org"})

      assert {:error, changeset} =
               Accounts.create_organization(%{handle: "taken-org", name: "Other Org"})

      assert "has already been taken" in errors_on(changeset).handle
    end
  end

  describe "organization registration changeset" do
    test "validates required fields" do
      changeset = Accounts.change_organization_registration()
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).handle
    end

    test "validates handle format" do
      changeset =
        Accounts.change_organization_registration(%{"name" => "Example", "handle" => "bad_org"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end
  end

  describe "users" do
    test "get_or_create_user_by_email/1 creates a new user with account" do
      assert {:ok, %User{} = user} = Accounts.get_or_create_user_by_email("new@example.com")
      assert user.email == "new@example.com"
      assert user.account != nil
      assert Account.user?(user.account)
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
      {:ok, _} = Accounts.get_or_create_user_by_email("john@other.com")
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
      assert {:ok, %Token{} = token} = Accounts.initiate_login("login@example.com")
      assert token.token != nil
      assert token.purpose == :login
      assert token.expires_at != nil
      assert token.used_at == nil
    end

    test "initiate_login/1 creates user if not exists" do
      assert {:ok, %Token{}} = Accounts.initiate_login("newlogin@example.com")
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
      updated_token = Repo.get!(Token, token.id)
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

    test "Token.valid?/1 returns true for valid token" do
      {:ok, token} = Accounts.initiate_login("validcheck@example.com")
      assert Token.valid?(token)
    end

    test "Token.valid?/1 returns false for used token" do
      {:ok, token} = Accounts.initiate_login("usedcheck@example.com")
      used_token = %{token | used_at: DateTime.utc_now()}
      refute Token.valid?(used_token)
    end

    test "Token.valid?/1 returns false for expired token" do
      {:ok, token} = Accounts.initiate_login("expiredcheck@example.com")
      expired_token = %{token | expires_at: ~U[2020-01-01 00:00:00Z]}
      refute Token.valid?(expired_token)
    end
  end
end
