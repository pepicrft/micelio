defmodule Micelio.Accounts do
  @moduledoc """
  The Accounts context handles user registration, authentication, and account management.
  """

  import Ecto.Query

  alias Micelio.Accounts.{Account, User, LoginToken}
  alias Micelio.Repo

  # =============================================================================
  # Accounts
  # =============================================================================

  @doc """
  Gets an account by ID.
  """
  def get_account(id), do: Repo.get(Account, id)

  @doc """
  Gets an account by handle (case-insensitive).
  """
  def get_account_by_handle(handle) do
    Account
    |> where([a], fragment("lower(?)", a.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Creates a new account.
  """
  def create_account(attrs) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks if a handle is available.
  """
  def handle_available?(handle) do
    normalized = String.downcase(handle)

    normalized not in Micelio.Handles.reserved() and
      is_nil(get_account_by_handle(handle))
  end

  # =============================================================================
  # Users
  # =============================================================================

  @doc """
  Gets a user by ID.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by ID with their account preloaded.
  """
  def get_user_with_account(id) do
    User
    |> Repo.get(id)
    |> Repo.preload(:account)
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc """
  Creates a new user with an associated personal account.
  If the user with this email already exists, returns the existing user.
  """
  def get_or_create_user_by_email(email) do
    case get_user_by_email(email) do
      nil -> create_user_with_account(email)
      user -> {:ok, Repo.preload(user, :account)}
    end
  end

  defp create_user_with_account(email) do
    handle = generate_handle_from_email(email)

    Repo.transaction(fn ->
      with {:ok, account} <- create_account(%{type: :user, handle: handle}),
           {:ok, user} <- create_user(%{email: email, account_id: account.id}) do
        %{user | account: account}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp generate_handle_from_email(email) do
    base =
      email
      |> String.split("@")
      |> List.first()
      |> String.replace(~r/[^a-z0-9-]/i, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")
      |> String.slice(0, 30)

    ensure_unique_handle(base)
  end

  defp ensure_unique_handle(base, suffix \\ nil) do
    handle = if suffix, do: "#{base}-#{suffix}", else: base

    if handle_available?(handle) do
      handle
    else
      new_suffix = if suffix, do: suffix + 1, else: 1
      ensure_unique_handle(base, new_suffix)
    end
  end

  # =============================================================================
  # Authentication (Magic Link)
  # =============================================================================

  @doc """
  Initiates the login flow by creating a login token for the user.
  If the user doesn't exist, creates them first.
  Returns {:ok, token} or {:error, reason}.
  """
  def initiate_login(email) do
    with {:ok, user} <- get_or_create_user_by_email(email) do
      create_login_token(user)
    end
  end

  @doc """
  Verifies a login token and returns the user if valid.
  Marks the token as used.
  """
  def verify_login_token(token) do
    case get_valid_login_token(token) do
      nil ->
        {:error, :invalid_token}

      login_token ->
        login_token
        |> LoginToken.use_changeset()
        |> Repo.update()

        {:ok, Repo.preload(login_token.user, :account)}
    end
  end

  defp create_login_token(user) do
    %LoginToken{}
    |> LoginToken.changeset(%{user_id: user.id})
    |> Repo.insert()
  end

  defp get_valid_login_token(token) do
    now = DateTime.utc_now()

    LoginToken
    |> where([lt], lt.token == ^token)
    |> where([lt], is_nil(lt.used_at))
    |> where([lt], lt.expires_at > ^now)
    |> preload(:user)
    |> Repo.one()
  end

  # =============================================================================
  # Organizations
  # =============================================================================

  @doc """
  Creates a new organization account.
  """
  def create_organization(attrs) do
    attrs
    |> Map.put(:type, :organization)
    |> create_account()
  end
end
