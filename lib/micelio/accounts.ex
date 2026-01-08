defmodule Micelio.Accounts do
  @moduledoc """
  The Accounts context handles user registration, authentication, and account management.
  """

  import Ecto.Query

  alias Micelio.Accounts.{Account, Organization, User, Token}
  alias Micelio.Repo

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
  Creates a new account for a user.
  """
  def create_user_account(attrs) do
    %Account{}
    |> Account.user_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a new account for an organization.
  """
  def create_organization_account(attrs) do
    %Account{}
    |> Account.organization_changeset(attrs)
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
      with {:ok, user} <- create_user(%{email: email}),
           {:ok, account} <- create_user_account(%{handle: handle, user_id: user.id}) do
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
  def verify_login_token(token_string) do
    with %Token{} = token <- get_valid_token(token_string, :login),
         {:ok, _} <- token |> Token.use_changeset() |> Repo.update() do
      {:ok, Repo.preload(token.user, :account)}
    else
      nil -> {:error, :invalid_token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp create_login_token(user) do
    %Token{}
    |> Token.changeset(%{user_id: user.id, purpose: :login})
    |> Repo.insert()
  end

  defp get_valid_token(token_string, purpose) do
    now = DateTime.utc_now()

    Token
    |> where([t], t.token == ^token_string)
    |> where([t], t.purpose == ^purpose)
    |> where([t], is_nil(t.used_at))
    |> where([t], t.expires_at > ^now)
    |> preload(:user)
    |> Repo.one()
  end

  @doc """
  Creates a new organization with an associated account.
  """
  def create_organization(attrs) do
    handle = Map.get(attrs, :handle) || Map.get(attrs, "handle")
    name = Map.get(attrs, :name) || Map.get(attrs, "name")

    Repo.transaction(fn ->
      with {:ok, org} <- do_create_organization(%{name: name}),
           {:ok, account} <-
             create_organization_account(%{handle: handle, organization_id: org.id}) do
        %{org | account: account}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp do_create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end
end
