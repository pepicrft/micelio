defmodule Micelio.ProjectsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Projects.Project

  describe "Project changeset" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("project-test@example.com")
      {:ok, account: user.account}
    end

    test "validates required fields", %{account: _account} do
      changeset = Project.changeset(%Project{}, %{})
      assert "can't be blank" in errors_on(changeset).handle
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "validates single character handle is valid", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{account_id: account.id, handle: "a", name: "Test"})

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle maximum length", %{account: account} do
      long_handle = String.duplicate("a", 101)

      changeset =
        Project.changeset(%Project{}, %{account_id: account.id, handle: long_handle, name: "Test"})

      assert "should be at most 100 character(s)" in errors_on(changeset).handle
    end

    test "validates handle format - no special characters", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{
          account_id: account.id,
          handle: "test_project",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - can contain hyphens in middle", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{
          account_id: account.id,
          handle: "test-project",
          name: "Test"
        })

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle format - cannot end with hyphen", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{
          account_id: account.id,
          handle: "testproject-",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot have consecutive hyphens", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{
          account_id: account.id,
          handle: "test--project",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot start with hyphen", %{account: account} do
      changeset =
        Project.changeset(%Project{}, %{
          account_id: account.id,
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
      {:ok, user} = Accounts.get_or_create_user_by_email("create-project@example.com")
      {:ok, account: user.account}
    end

    test "creates a project with valid attributes", %{account: account} do
      attrs = %{handle: "my-project", name: "My Project", account_id: account.id}
      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.handle == "my-project"
      assert project.name == "My Project"
      assert project.account_id == account.id
    end

    test "creates a project with description", %{account: account} do
      attrs = %{
        handle: "described-project",
        name: "Described Project",
        description: "A project with a description",
        account_id: account.id
      }

      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.description == "A project with a description"
    end

    test "fails with duplicate handle for same account", %{account: account} do
      attrs = %{handle: "duplicate", name: "First", account_id: account.id}
      assert {:ok, _} = Projects.create_project(attrs)

      duplicate_attrs = %{handle: "duplicate", name: "Second", account_id: account.id}
      assert {:error, changeset} = Projects.create_project(duplicate_attrs)
      assert "has already been taken for this account" in errors_on(changeset).handle
    end

    test "allows same handle for different accounts", %{account: account1} do
      {:ok, user2} = Accounts.get_or_create_user_by_email("other-account@example.com")
      account2 = user2.account

      attrs1 = %{handle: "shared-handle", name: "First", account_id: account1.id}
      attrs2 = %{handle: "shared-handle", name: "Second", account_id: account2.id}

      assert {:ok, project1} = Projects.create_project(attrs1)
      assert {:ok, project2} = Projects.create_project(attrs2)

      assert project1.handle == project2.handle
      refute project1.account_id == project2.account_id
    end
  end

  describe "get_project/1" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("get-project@example.com")

      {:ok, project} =
        Projects.create_project(%{handle: "findme", name: "Find Me", account_id: user.account.id})

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
      {:ok, user} = Accounts.get_or_create_user_by_email("handle-lookup@example.com")

      {:ok, project} =
        Projects.create_project(%{
          handle: "by-handle",
          name: "By Handle",
          account_id: user.account.id
        })

      {:ok, account: user.account, project: project}
    end

    test "returns the project", %{account: account, project: project} do
      assert Projects.get_project_by_handle(account.id, "by-handle").id == project.id
    end

    test "is case-insensitive", %{account: account, project: project} do
      assert Projects.get_project_by_handle(account.id, "BY-HANDLE").id == project.id
    end

    test "returns nil for non-existent handle", %{account: account} do
      assert Projects.get_project_by_handle(account.id, "nonexistent") == nil
    end

    test "returns nil for different account", %{project: project} do
      {:ok, other_user} = Accounts.get_or_create_user_by_email("other-lookup@example.com")
      assert Projects.get_project_by_handle(other_user.account.id, project.handle) == nil
    end
  end

  describe "list_projects_for_account/1" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("list-projects@example.com")
      {:ok, account: user.account}
    end

    test "returns empty list when no projects", %{account: account} do
      assert Projects.list_projects_for_account(account.id) == []
    end

    test "returns all projects for account ordered by name", %{account: account} do
      {:ok, p1} =
        Projects.create_project(%{handle: "zebra", name: "Zebra", account_id: account.id})

      {:ok, p2} =
        Projects.create_project(%{handle: "alpha", name: "Alpha", account_id: account.id})

      {:ok, p3} =
        Projects.create_project(%{handle: "middle", name: "Middle", account_id: account.id})

      projects = Projects.list_projects_for_account(account.id)
      assert length(projects) == 3
      assert Enum.map(projects, & &1.id) == [p2.id, p3.id, p1.id]
    end

    test "does not return projects from other accounts", %{account: account} do
      {:ok, _} = Projects.create_project(%{handle: "mine", name: "Mine", account_id: account.id})

      {:ok, other_user} = Accounts.get_or_create_user_by_email("other-list@example.com")

      {:ok, _} =
        Projects.create_project(%{
          handle: "theirs",
          name: "Theirs",
          account_id: other_user.account.id
        })

      projects = Projects.list_projects_for_account(account.id)
      assert length(projects) == 1
      assert hd(projects).handle == "mine"
    end
  end

  describe "update_project/2" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("update-project@example.com")

      {:ok, project} =
        Projects.create_project(%{
          handle: "original",
          name: "Original",
          account_id: user.account.id
        })

      {:ok, project: project, account: user.account}
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
      {:ok, user} = Accounts.get_or_create_user_by_email("delete-project@example.com")

      {:ok, project} =
        Projects.create_project(%{
          handle: "deleteme",
          name: "Delete Me",
          account_id: user.account.id
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
      {:ok, user} = Accounts.get_or_create_user_by_email("handle-available@example.com")

      {:ok, _} =
        Projects.create_project(%{handle: "taken", name: "Taken", account_id: user.account.id})

      {:ok, account: user.account}
    end

    test "returns true for available handles", %{account: account} do
      assert Projects.handle_available?(account.id, "available")
    end

    test "returns false for taken handles", %{account: account} do
      refute Projects.handle_available?(account.id, "taken")
    end

    test "returns false for taken handles (case-insensitive)", %{account: account} do
      refute Projects.handle_available?(account.id, "TAKEN")
    end

    test "returns true for same handle in different account" do
      {:ok, other_user} = Accounts.get_or_create_user_by_email("other-available@example.com")
      assert Projects.handle_available?(other_user.account.id, "taken")
    end
  end
end
