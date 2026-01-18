defmodule Micelio.Authorization.ProjectVisibilityTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Projects

  setup do
    unique = System.unique_integer([:positive])

    {:ok, owner} = Accounts.get_or_create_user_by_email("project-owner-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "proj-org-#{unique}",
        name: "Project Org #{unique}"
      })

    {:ok, public_project} =
      Projects.create_project(%{
        handle: "public-#{unique}",
        name: "Public Project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, private_project} =
      Projects.create_project(%{
        handle: "private-#{unique}",
        name: "Private Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, member} = Accounts.get_or_create_user_by_email("project-member-#{unique}@example.com")

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "user"
      })

    {:ok, outsider} =
      Accounts.get_or_create_user_by_email("project-outsider-#{unique}@example.com")

    %{
      public_project: public_project,
      private_project: private_project,
      member: member,
      outsider: outsider
    }
  end

  test "allows unauthenticated reads for public projects", %{public_project: public_project} do
    assert :ok = Authorization.authorize(:project_read, nil, public_project)
  end

  test "denies unauthenticated reads for private projects", %{private_project: private_project} do
    assert {:error, :forbidden} = Authorization.authorize(:project_read, nil, private_project)
  end

  test "allows organization members to read private projects", %{
    private_project: private_project,
    member: member
  } do
    assert :ok = Authorization.authorize(:project_read, member, private_project)
  end

  test "denies non-members for private projects", %{
    private_project: private_project,
    outsider: outsider
  } do
    assert {:error, :forbidden} =
             Authorization.authorize(:project_read, outsider, private_project)
  end
end
