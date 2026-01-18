defmodule Micelio.Accounts.Account do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :handle, :string

    belongs_to :user, Micelio.Accounts.User
    belongs_to :organization, Micelio.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new account for a user.
  """
  def user_changeset(account, attrs, opts \\ []) do
    allow_reserved = Keyword.get(opts, :allow_reserved, false)

    account
    |> cast(attrs, [:handle, :user_id])
    |> validate_required([:handle, :user_id])
    |> validate_handle(allow_reserved)
    |> unique_constraint(:handle, name: :accounts_handle_index)
    |> assoc_constraint(:user)
    |> validate_owner_exclusive()
  end

  @doc """
  Changeset for creating a new account for an organization.
  """
  def organization_changeset(account, attrs, opts \\ []) do
    allow_reserved = Keyword.get(opts, :allow_reserved, false)

    account
    |> cast(attrs, [:handle, :organization_id])
    |> validate_required([:handle, :organization_id])
    |> validate_handle(allow_reserved)
    |> unique_constraint(:handle, name: :accounts_handle_index)
    |> assoc_constraint(:organization)
    |> validate_owner_exclusive()
  end

  @doc """
  Returns true if this account belongs to a user.
  """
  def user?(%__MODULE__{user_id: user_id}), do: not is_nil(user_id)

  @doc """
  Returns true if this account belongs to an organization.
  """
  def organization?(%__MODULE__{organization_id: org_id}), do: not is_nil(org_id)

  defp validate_handle(changeset, allow_reserved) do
    changeset =
      changeset
      |> validate_format(:handle, ~r/^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}$/i,
        message:
          "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen"
      )
      |> validate_length(:handle, min: 1, max: 39)

    if allow_reserved do
      changeset
    else
      validate_exclusion(changeset, :handle, Micelio.Handles.reserved(), message: "is reserved")
    end
  end

  defp validate_owner_exclusive(changeset) do
    user_id = get_field(changeset, :user_id)
    org_id = get_field(changeset, :organization_id)

    cond do
      not is_nil(user_id) and not is_nil(org_id) ->
        add_error(changeset, :base, "account cannot belong to both a user and an organization")

      is_nil(user_id) and is_nil(org_id) ->
        add_error(changeset, :base, "account must belong to either a user or an organization")

      true ->
        changeset
    end
  end
end
