defmodule Micelio.Authorization.Checks do
  @moduledoc false

  alias Micelio.Accounts
  alias Micelio.Accounts.{Account, Organization, User}
  alias Micelio.Projects.Project

  def authenticated_as_user(%User{}, _resource), do: true
  def authenticated_as_user(_, _resource), do: false

  def organization_member(%User{} = user, %Organization{id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(%User{} = user, %Project{organization_id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(%User{} = user, organization_id) when is_binary(organization_id),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(_, _), do: false

  def organization_owner(%User{} = user, %Organization{id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, "owner")

  def organization_owner(%User{} = user, %Project{organization_id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, "owner")

  def organization_owner(%User{} = user, organization_id) when is_binary(organization_id),
    do: Accounts.user_role_in_organization?(user, organization_id, "owner")

  def organization_owner(_, _), do: false

  def repository_member(%User{} = user, %Account{} = account),
    do: Accounts.user_has_account_access?(user, account)

  def repository_member(%User{} = user, %{account: %Account{} = account}),
    do: Accounts.user_has_account_access?(user, account)

  def repository_member(%User{} = user, %{organization_id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def repository_member(_, _), do: false

  def repository_owner(%User{} = user, %Account{} = account),
    do:
      Accounts.user_owns_account?(user, account) or
        Accounts.user_role_in_organization?(user, account.organization_id, "owner")

  def repository_owner(%User{} = user, %{account: %Account{} = account}),
    do: repository_owner(user, account)

  def repository_owner(%User{} = user, %{organization_id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, "owner")

  def repository_owner(_, _), do: false
end
