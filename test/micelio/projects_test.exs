defmodule Micelio.ProjectsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Projects.Project

  describe "Project changeset" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "project-test", name: "Project Test"})

      {:ok, organization: organization}
    end

    test "validates required fields", %{organization: _organization} do
      changeset = Project.changeset(%Project{}, %{})
      assert "can't be blank" in errors_on(changeset).handle
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).organization_id
    end

    test "validates single character handle is valid", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "a",
          name: "Test"
        })

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle maximum length", %{organization: organization} do
      long_handle = String.duplicate("a", 101)

      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: long_handle,
          name: "Test"
        })

      assert "should be at most 100 character(s)" in errors_on(changeset).handle
    end

    test "validates handle format - no special characters", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "test_project",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - can contain hyphens in middle", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "test-project",
          name: "Test"
        })

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle format - cannot end with hyphen", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "testproject-",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot have consecutive hyphens",
         %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "test--project",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot start with hyphen", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "-testproject",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end
  end

  describe "create_project/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "create-project", name: "Create Project"})

      {:ok, organization: organization}
    end

    test "creates a project with valid attributes", %{organization: organization} do
      attrs = %{handle: "my-project", name: "My Project", organization_id: organization.id}
      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.handle == "my-project"
      assert project.name == "My Project"
      assert project.organization_id == organization.id
    end

    test "creates a project with description", %{organization: organization} do
      attrs = %{
        handle: "described-project",
        name: "Described Project",
        description: "A project with a description",
        organization_id: organization.id
      }

      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.description == "A project with a description"
    end

    test "fails with duplicate handle for same organization", %{organization: organization} do
      attrs = %{handle: "duplicate", name: "First", organization_id: organization.id}
      assert {:ok, _} = Projects.create_project(attrs)

      duplicate_attrs = %{handle: "duplicate", name: "Second", organization_id: organization.id}
      assert {:error, changeset} = Projects.create_project(duplicate_attrs)
      assert "has already been taken for this organization" in errors_on(changeset).handle
    end

    test "allows same handle for different organizations", %{organization: organization1} do
      {:ok, organization2} =
        Accounts.create_organization(%{handle: "other-org", name: "Other Org"})

      attrs1 = %{handle: "shared-handle", name: "First", organization_id: organization1.id}
      attrs2 = %{handle: "shared-handle", name: "Second", organization_id: organization2.id}

      assert {:ok, project1} = Projects.create_project(attrs1)
      assert {:ok, project2} = Projects.create_project(attrs2)

      assert project1.handle == project2.handle
      refute project1.organization_id == project2.organization_id
    end
  end

  describe "get_project/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "get-project", name: "Get Project"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "findme",
          name: "Find Me",
          organization_id: organization.id
        })

      {:ok, project: project}
    end

    test "returns the project", %{project: project} do
      assert Projects.get_project(project.id).id == project.id
    end

    test "returns nil for non-existent id" do
      assert Projects.get_project(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_project_by_handle/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "handle-lookup", name: "Handle Lookup"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "by-handle",
          name: "By Handle",
          organization_id: organization.id
        })

      {:ok, organization: organization, project: project}
    end

    test "returns the project", %{organization: organization, project: project} do
      assert Projects.get_project_by_handle(organization.id, "by-handle").id == project.id
    end

    test "is case-insensitive", %{organization: organization, project: project} do
      assert Projects.get_project_by_handle(organization.id, "BY-HANDLE").id == project.id
    end

    test "returns nil for non-existent handle", %{organization: organization} do
      assert Projects.get_project_by_handle(organization.id, "nonexistent") == nil
    end

    test "returns nil for different organization", %{project: project} do
      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-lookup", name: "Other Lookup"})

      assert Projects.get_project_by_handle(other_org.id, project.handle) == nil
    end
  end

  describe "list_projects_for_organization/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "list-projects", name: "List Projects"})

      {:ok, organization: organization}
    end

    test "returns empty list when no projects", %{organization: organization} do
      assert Projects.list_projects_for_organization(organization.id) == []
    end

    test "returns all projects for organization ordered by name", %{organization: organization} do
      {:ok, p1} =
        Projects.create_project(%{
          handle: "zebra",
          name: "Zebra",
          organization_id: organization.id
        })

      {:ok, p2} =
        Projects.create_project(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: organization.id
        })

      {:ok, p3} =
        Projects.create_project(%{
          handle: "middle",
          name: "Middle",
          organization_id: organization.id
        })

      projects = Projects.list_projects_for_organization(organization.id)
      assert length(projects) == 3
      assert Enum.map(projects, & &1.id) == [p2.id, p3.id, p1.id]
    end

    test "does not return projects from other organizations", %{organization: organization} do
      {:ok, _} =
        Projects.create_project(%{
          handle: "mine",
          name: "Mine",
          organization_id: organization.id
        })

      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-list", name: "Other List"})

      {:ok, _} =
        Projects.create_project(%{
          handle: "theirs",
          name: "Theirs",
          organization_id: other_org.id
        })

      projects = Projects.list_projects_for_organization(organization.id)
      assert length(projects) == 1
      assert hd(projects).handle == "mine"
    end
  end

  describe "list_projects_for_user/1" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("projects-user@example.com")

      {:ok, org_one} =
        Accounts.create_organization_for_user(user, %{
          handle: "user-org-one",
          name: "User Org One"
        })

      {:ok, org_two} =
        Accounts.create_organization_for_user(user, %{
          handle: "user-org-two",
          name: "User Org Two"
        })

      {:ok, _} =
        Projects.create_project(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: org_one.id
        })

      {:ok, _} =
        Projects.create_project(%{
          handle: "beta",
          name: "Beta",
          organization_id: org_two.id
        })

      {:ok, user: user, org_one: org_one, org_two: org_two}
    end

    test "returns projects scoped to memberships ordered by organization handle",
         %{user: user, org_one: org_one, org_two: org_two} do
      projects = Projects.list_projects_for_user(user)
      assert Enum.count(projects) == 2

      handles = Enum.map(projects, & &1.organization.account.handle)
      assert handles == [org_one.account.handle, org_two.account.handle]
    end
  end

  describe "update_project/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "update-project", name: "Update Project"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "original",
          name: "Original",
          organization_id: organization.id
        })

      {:ok, project: project, organization: organization}
    end

    test "updates project name", %{project: project} do
      assert {:ok, updated} = Projects.update_project(project, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
      assert updated.handle == "original"
    end

    test "updates project description", %{project: project} do
      assert {:ok, updated} = Projects.update_project(project, %{description: "New description"})
      assert updated.description == "New description"
    end

    test "updates project handle", %{project: project} do
      assert {:ok, updated} = Projects.update_project(project, %{handle: "new-handle"})
      assert updated.handle == "new-handle"
    end

    test "fails with invalid handle", %{project: project} do
      assert {:error, changeset} = Projects.update_project(project, %{handle: "invalid_handle"})
      assert Map.has_key?(errors_on(changeset), :handle)
    end
  end

  describe "delete_project/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "delete-project", name: "Delete Project"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "deleteme",
          name: "Delete Me",
          organization_id: organization.id
        })

      {:ok, project: project}
    end

    test "deletes the project", %{project: project} do
      assert {:ok, _} = Projects.delete_project(project)
      assert Projects.get_project(project.id) == nil
    end
  end

  describe "handle_available?/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "handle-available", name: "Handle Available"})

      {:ok, _} =
        Projects.create_project(%{
          handle: "taken",
          name: "Taken",
          organization_id: organization.id
        })

      {:ok, organization: organization}
    end

    test "returns true for available handles", %{organization: organization} do
      assert Projects.handle_available?(organization.id, "available")
    end

    test "returns false for taken handles", %{organization: organization} do
      refute Projects.handle_available?(organization.id, "taken")
    end

    test "returns false for taken handles (case-insensitive)", %{organization: organization} do
      refute Projects.handle_available?(organization.id, "TAKEN")
    end

    test "returns true for same handle in different organization" do
      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-available", name: "Other Available"})

      assert Projects.handle_available?(other_org.id, "taken")
    end
  end

  describe "get_project_for_user_by_handle/3" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("project-access@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{
          handle: "access-org",
          name: "Access Org"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "access-project",
          name: "Access Project",
          organization_id: organization.id
        })

      {:ok, user: user, organization: organization, project: project}
    end

    test "returns the project for authorized user", %{
      user: user,
      organization: organization,
      project: project
    } do
      assert {:ok, loaded, org} =
               Projects.get_project_for_user_by_handle(
                 user,
                 organization.account.handle,
                 project.handle
               )

      assert loaded.id == project.id
      assert org.id == organization.id
    end

    test "returns unauthorized for non-member", %{project: project} do
      {:ok, other_user} = Accounts.get_or_create_user_by_email("project-other@example.com")

      assert {:error, :unauthorized} =
               Projects.get_project_for_user_by_handle(
                 other_user,
                 "access-org",
                 project.handle
               )
    end
  end
end
