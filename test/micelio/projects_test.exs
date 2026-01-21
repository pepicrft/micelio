defmodule Micelio.ProjectsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Accounts.OrganizationMembership
  alias Micelio.Mic.Repository, as: MicRepository
  alias Micelio.Projects
  alias Micelio.Projects.Project
  alias Micelio.Repo
  alias Micelio.Storage

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  describe "Project changeset" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          handle: unique_handle("project-test"),
          name: "Project Test"
        })

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

    test "validates visibility inclusion", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "visible-project",
          name: "Visible Project",
          visibility: "secret"
        })

      assert "is invalid" in errors_on(changeset).visibility
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
      assert project.visibility == "private"
    end

    test "uses the organization default LLM model when creating projects" do
      {:ok, organization} =
        Accounts.create_organization(%{
          handle: unique_handle("llm-default-org"),
          name: "LLM Default Org",
          llm_models: ["gpt-4.1"],
          llm_default_model: "gpt-4.1"
        })

      attrs = %{
        handle: unique_handle("llm-default"),
        name: "LLM Default",
        organization_id: organization.id
      }

      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.llm_model == "gpt-4.1"
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

    test "creates a project with url", %{organization: organization} do
      attrs = %{
        handle: "linked-project",
        name: "Linked Project",
        url: "https://example.com/linked-project",
        organization_id: organization.id
      }

      assert {:ok, %Project{} = project} = Projects.create_project(attrs)
      assert project.url == "https://example.com/linked-project"
    end

    test "rejects invalid url schemes", %{organization: organization} do
      changeset =
        Project.changeset(%Project{}, %{
          organization_id: organization.id,
          handle: "bad-url",
          name: "Bad Url",
          url: "javascript:alert(1)"
        })

      assert "must be a valid http(s) URL" in errors_on(changeset).url
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

    test "enforces project limit per organization", %{organization: organization} do
      limit =
        :micelio
        |> Application.get_env(:project_limits, [])
        |> Keyword.get(:max_projects_per_tenant, 25)

      assert is_integer(limit) and limit > 0

      for idx <- 1..limit do
        attrs = %{
          handle: "limit-#{idx}",
          name: "Limit #{idx}",
          organization_id: organization.id
        }

        assert {:ok, _project} = Projects.create_project(attrs)
      end

      extra_attrs = %{
        handle: "limit-extra",
        name: "Limit Extra",
        organization_id: organization.id
      }

      assert {:error, changeset} = Projects.create_project(extra_attrs)

      assert "project limit reached for this organization" in errors_on(changeset).base
    end
  end

  describe "fork_project/3" do
    setup do
      {:ok, source_org} =
        Accounts.create_organization(%{handle: "source-org", name: "Source Org"})

      {:ok, target_org} =
        Accounts.create_organization(%{handle: "fork-org", name: "Fork Org"})

      {:ok, source} =
        Projects.create_project(%{
          handle: "source-project",
          name: "Source Project",
          description: "Original description",
          url: "https://example.com/source",
          visibility: "public",
          organization_id: source_org.id
        })

      {:ok, source: source, target_org: target_org}
    end

    test "creates a fork with origin tracking and copied storage", %{
      source: source,
      target_org: target_org
    } do
      head_key = MicRepository.head_key(source.id)
      blob_hash = <<1::256>>
      blob_key = MicRepository.blob_key(source.id, blob_hash)

      assert {:ok, _} = Storage.put(head_key, "head-data")
      assert {:ok, _} = Storage.put(blob_key, "blob-data")

      assert {:ok, %Project{} = forked} =
               Projects.fork_project(source, target_org, %{
                 handle: "source-fork",
                 name: "Source Fork"
               })

      assert forked.forked_from_id == source.id
      assert forked.organization_id == target_org.id
      assert forked.handle == "source-fork"
      assert forked.name == "Source Fork"
      assert forked.description == source.description
      assert forked.url == source.url
      assert forked.visibility == source.visibility

      assert {:ok, "head-data"} = Storage.get(MicRepository.head_key(forked.id))
      assert {:ok, "blob-data"} = Storage.get(MicRepository.blob_key(forked.id, blob_hash))
    end

    test "rejects fork when project limit is reached", %{source: source, target_org: target_org} do
      limit =
        :micelio
        |> Application.get_env(:project_limits, [])
        |> Keyword.get(:max_projects_per_tenant, 25)

      assert is_integer(limit) and limit > 0

      for idx <- 1..limit do
        attrs = %{
          handle: "fork-limit-#{idx}",
          name: "Fork Limit #{idx}",
          organization_id: target_org.id
        }

        assert {:ok, _project} = Projects.create_project(attrs)
      end

      assert {:error, changeset} =
               Projects.fork_project(source, target_org, %{
                 handle: "fork-over-limit",
                 name: "Fork Over Limit"
               })

      assert "project limit reached for this organization" in errors_on(changeset).base
    end

    test "returns errors when fork data is invalid", %{source: source, target_org: target_org} do
      assert {:error, changeset} =
               Projects.fork_project(source, target_org, %{
                 handle: "invalid handle",
                 name: "Fork"
               })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "defaults handle and name to the source project", %{
      source: source,
      target_org: target_org
    } do
      assert {:ok, %Project{} = forked} = Projects.fork_project(source, target_org)

      assert forked.handle == source.handle
      assert forked.name == source.name
      assert forked.forked_from_id == source.id
    end
  end

  describe "project stars" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("starred@example.com")

      {:ok, organization} =
        Accounts.create_organization(%{handle: "star-org", name: "Star Org"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "star-project",
          name: "Star Project",
          organization_id: organization.id
        })

      {:ok, user: user, project: project}
    end

    test "stars and unstars a project", %{user: user, project: project} do
      refute Projects.project_starred?(user, project)
      assert Projects.count_project_stars(project) == 0

      assert {:ok, _star} = Projects.star_project(user, project)
      assert Projects.project_starred?(user, project)
      assert Projects.count_project_stars(project) == 1

      assert {:ok, _star} = Projects.unstar_project(user, project)
      refute Projects.project_starred?(user, project)
      assert Projects.count_project_stars(project) == 0
    end

    test "star_project/2 is idempotent", %{user: user, project: project} do
      assert {:ok, _star} = Projects.star_project(user, project)
      assert {:ok, _star} = Projects.star_project(user, project)
      assert Projects.count_project_stars(project) == 1
    end

    test "unstar_project/2 returns ok when no star exists", %{user: user, project: project} do
      assert {:ok, :not_found} = Projects.unstar_project(user, project)
      refute Projects.project_starred?(user, project)
    end

    test "counts stars across multiple users", %{user: user, project: project} do
      {:ok, other_user} = Accounts.get_or_create_user_by_email("starred-2@example.com")

      assert {:ok, _star} = Projects.star_project(user, project)
      assert {:ok, _star} = Projects.star_project(other_user, project)
      assert Projects.count_project_stars(project) == 2

      assert {:ok, _star} = Projects.unstar_project(user, project)
      assert Projects.count_project_stars(project) == 1
    end
  end

  describe "list_starred_projects_for_user/1" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("favorites@example.com")
      {:ok, other_user} = Accounts.get_or_create_user_by_email("favorites-2@example.com")

      {:ok, organization} =
        Accounts.create_organization(%{handle: "favorite-org", name: "Favorite Org"})

      {:ok, first_project} =
        Projects.create_project(%{
          handle: "first-favorite",
          name: "First Favorite",
          organization_id: organization.id
        })

      {:ok, second_project} =
        Projects.create_project(%{
          handle: "second-favorite",
          name: "Second Favorite",
          organization_id: organization.id
        })

      {:ok,
       user: user,
       other_user: other_user,
       organization: organization,
       first_project: first_project,
       second_project: second_project}
    end

    test "returns starred projects for the user", %{
      user: user,
      other_user: other_user,
      first_project: first_project,
      second_project: second_project,
      organization: organization
    } do
      assert Projects.list_starred_projects_for_user(user) == []

      assert {:ok, _star} = Projects.star_project(user, first_project)
      assert {:ok, _star} = Projects.star_project(user, second_project)
      assert {:ok, _star} = Projects.star_project(other_user, first_project)

      starred = Projects.list_starred_projects_for_user(user)
      starred_ids = Enum.map(starred, & &1.id) |> Enum.sort()

      assert starred_ids == Enum.sort([first_project.id, second_project.id])

      first_entry = Enum.find(starred, &(&1.id == first_project.id))
      assert first_entry.organization.account.handle == organization.account.handle
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

  describe "list_public_projects_for_organization/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "list-public", name: "List Public"})

      {:ok, organization: organization}
    end

    test "returns only public projects", %{organization: organization} do
      {:ok, public_project} =
        Projects.create_project(%{
          handle: "public",
          name: "Public",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_project} =
        Projects.create_project(%{
          handle: "private",
          name: "Private",
          organization_id: organization.id,
          visibility: "private"
        })

      projects = Projects.list_public_projects_for_organization(organization.id)
      assert Enum.map(projects, & &1.id) == [public_project.id]
    end
  end

  describe "list_public_projects_for_organizations/1" do
    test "returns public projects across organizations with preloaded accounts" do
      {:ok, org_one} =
        Accounts.create_organization(%{handle: "list-org-a", name: "List Org A"})

      {:ok, org_two} =
        Accounts.create_organization(%{handle: "list-org-b", name: "List Org B"})

      {:ok, public_one} =
        Projects.create_project(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: org_one.id,
          visibility: "public"
        })

      {:ok, _private_one} =
        Projects.create_project(%{
          handle: "private",
          name: "Private",
          organization_id: org_one.id,
          visibility: "private"
        })

      {:ok, public_two} =
        Projects.create_project(%{
          handle: "beta",
          name: "Beta",
          organization_id: org_two.id,
          visibility: "public"
        })

      projects = Projects.list_public_projects_for_organizations([org_one.id, org_two.id])
      project_ids = Enum.map(projects, & &1.id)

      assert project_ids == [public_one.id, public_two.id]
      assert Enum.all?(projects, &is_binary(&1.organization.account.handle))
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

    test "allows clearing project url", %{project: project} do
      assert {:ok, updated} = Projects.update_project(project, %{url: "https://example.com/repo"})
      assert updated.url == "https://example.com/repo"

      assert {:ok, cleared} = Projects.update_project(updated, %{url: nil})
      assert cleared.url == nil
    end

    test "fails with invalid handle", %{project: project} do
      assert {:error, changeset} = Projects.update_project(project, %{handle: "invalid_handle"})
      assert Map.has_key?(errors_on(changeset), :handle)
    end
  end

  describe "update_project_settings/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "settings-project", name: "Settings Project"})

      {:ok, project} =
        Projects.create_project(%{
          handle: "settings-llm",
          name: "Settings LLM",
          organization_id: organization.id
        })

      {:ok, project: project}
    end

    test "updates the project LLM model", %{project: project} do
      assert {:ok, updated} = Projects.update_project_settings(project, %{llm_model: "gpt-4.1"})
      assert updated.llm_model == "gpt-4.1"
    end

    test "rejects invalid LLM models", %{project: project} do
      assert {:error, changeset} =
               Projects.update_project_settings(project, %{llm_model: "invalid-model"})

      assert Map.has_key?(errors_on(changeset), :llm_model)
    end
  end

  describe "update_project_settings/2 with organization LLM models" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          handle: unique_handle("settings-llm-org"),
          name: "Settings LLM Org",
          llm_models: ["gpt-4.1-mini"]
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: unique_handle("settings-llm-repo"),
          name: "Settings LLM Repo",
          organization_id: organization.id
        })

      {:ok, project: project}
    end

    test "rejects LLM models outside the organization list", %{project: project} do
      assert {:error, changeset} =
               Projects.update_project_settings(project, %{llm_model: "gpt-4.1"})

      assert Map.has_key?(errors_on(changeset), :llm_model)
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

      {:ok, public_project} =
        Projects.create_project(%{
          handle: "public-project",
          name: "Public Project",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok,
       user: user, organization: organization, project: project, public_project: public_project}
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

    test "returns public project for anonymous user", %{
      organization: organization,
      public_project: public_project
    } do
      assert {:ok, loaded, org} =
               Projects.get_project_for_user_by_handle(
                 nil,
                 organization.account.handle,
                 public_project.handle
               )

      assert loaded.id == public_project.id
      assert org.id == organization.id
    end
  end

  describe "search_projects/2" do
    test "returns public projects for anonymous users" do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "search-org", name: "Search Org"})

      {:ok, public_project} =
        Projects.create_project(%{
          handle: "public-repo",
          name: "Searchable Project",
          description: "Fast search for repositories",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_project} =
        Projects.create_project(%{
          handle: "private-repo",
          name: "Private Searchable",
          description: "Search secrets",
          organization_id: organization.id,
          visibility: "private"
        })

      results = Projects.search_projects("search", user: nil)

      assert Enum.any?(results, &(&1.id == public_project.id))
      refute Enum.any?(results, &(&1.handle == "private-repo"))
    end

    test "includes private projects for members" do
      {:ok, user} = Accounts.get_or_create_user_by_email("searcher@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{handle: "member-org", name: "Member Org"})

      {:ok, private_project} =
        Projects.create_project(%{
          handle: "member-repo",
          name: "Secret Search",
          description: "Private search target",
          organization_id: organization.id,
          visibility: "private"
        })

      results = Projects.search_projects("secret", user: user)

      assert Enum.any?(results, &(&1.id == private_project.id))
    end

    test "returns empty list for blank queries" do
      assert [] == Projects.search_projects("   ", user: nil)
    end

    test "matches terms in descriptions" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "desc-org-#{unique}",
          name: "Description Org #{unique}"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "desc-repo-#{unique}",
          name: "Plain Project",
          description: "A nebula of repository search terms",
          organization_id: organization.id,
          visibility: "public"
        })

      results = Projects.search_projects("nebula", user: nil)

      assert Enum.any?(results, &(&1.id == project.id))
    end

    test "matches terms in names when descriptions are empty" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "name-org-#{unique}",
          name: "Name Org #{unique}"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "name-repo-#{unique}",
          name: "Aurora Search",
          description: nil,
          organization_id: organization.id,
          visibility: "public"
        })

      results = Projects.search_projects("aurora", user: nil)

      assert Enum.any?(results, &(&1.id == project.id))
    end

    test "matches terms split across name and description" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "split-org-#{unique}",
          name: "Split Org #{unique}"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "split-repo-#{unique}",
          name: "Alpha Discovery",
          description: "Beta catalog entry",
          organization_id: organization.id,
          visibility: "public"
        })

      results = Projects.search_projects("alpha beta", user: nil)

      assert Enum.any?(results, &(&1.id == project.id))
    end
  end

  describe "list_popular_projects/1" do
    test "returns public projects ordered by stars with counts" do
      unique = System.unique_integer([:positive])

      {:ok, organization_one} =
        Accounts.create_organization(%{
          handle: "popular-org-#{unique}",
          name: "Popular Org #{unique}"
        })

      {:ok, organization_two} =
        Accounts.create_organization(%{
          handle: "popular-org-2-#{unique}",
          name: "Popular Org 2 #{unique}"
        })

      {:ok, star_user_one} =
        Accounts.get_or_create_user_by_email("popular-star-#{unique}@example.com")

      {:ok, star_user_two} =
        Accounts.get_or_create_user_by_email("popular-star-2-#{unique}@example.com")

      {:ok, project_top} =
        Projects.create_project(%{
          handle: "popular-top-#{unique}",
          name: "Popular Top",
          description: "Top project",
          organization_id: organization_one.id,
          visibility: "public"
        })

      {:ok, project_secondary} =
        Projects.create_project(%{
          handle: "popular-secondary-#{unique}",
          name: "Popular Secondary",
          description: "Secondary project",
          organization_id: organization_two.id,
          visibility: "public"
        })

      {:ok, _project_private} =
        Projects.create_project(%{
          handle: "popular-private-#{unique}",
          name: "Popular Private",
          description: "Private project",
          organization_id: organization_two.id,
          visibility: "private"
        })

      assert {:ok, _} = Projects.star_project(star_user_one, project_top)
      assert {:ok, _} = Projects.star_project(star_user_two, project_top)
      assert {:ok, _} = Projects.star_project(star_user_one, project_secondary)

      results = Projects.list_popular_projects(limit: 10, offset: 0)

      assert Enum.map(results, & &1.id) == [project_top.id, project_secondary.id]
      assert Enum.map(results, & &1.star_count) == [2, 1]
    end
  end

  describe "ensure_micelio_workspace/0" do
    test "creates the micelio org, membership, and project" do
      assert {:ok, %{user: user, organization: organization, project: project}} =
               Projects.ensure_micelio_workspace()

      assert user.email == "micelio@micelio.dev"
      assert organization.account.handle == "micelio"
      assert project.handle == "micelio"
      assert project.name == "Micelio"
      assert project.description == "The Micelio platform"
      assert project.url == "https://micelio.dev"
      assert project.visibility == "public"

      assert %OrganizationMembership{} =
               Repo.get_by(OrganizationMembership,
                 user_id: user.id,
                 organization_id: organization.id
               )
    end

    test "backfills missing project metadata and is idempotent" do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "micelio", name: "Micelio"},
          allow_reserved: true
        )

      {:ok, project} =
        Projects.create_project(%{
          handle: "micelio",
          name: "Micelio",
          organization_id: organization.id,
          visibility: "private"
        })

      assert project.description == nil
      assert project.url == nil

      assert {:ok, %{project: updated_project}} = Projects.ensure_micelio_workspace()
      assert updated_project.id == project.id
      assert updated_project.description == "The Micelio platform"
      assert updated_project.url == "https://micelio.dev"
      assert updated_project.visibility == "public"

      assert {:ok, %{project: same_project}} = Projects.ensure_micelio_workspace()
      assert same_project.id == updated_project.id
    end
  end
end
