defmodule Micelio.ProjectsSearchTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects

  test "search_projects returns public matches for anonymous users" do
    user = create_user("searcher@example.com")
    org = create_org_for_user(user, "alpha", "Alpha Org")
    other_org = create_org("beta", "Beta Org")

    public_match =
      create_project(org, %{
        handle: "alpha-repo",
        name: "Alpha Tools",
        description: "Fast storage for docs",
        visibility: "public"
      })

    _private_match =
      create_project(org, %{
        handle: "alpha-secret",
        name: "Alpha Secret",
        description: "Storage for internal plans",
        visibility: "private"
      })

    public_other =
      create_project(other_org, %{
        handle: "beta-repo",
        name: "Beta Forge",
        description: "Storage for issues",
        visibility: "public"
      })

    results = Projects.search_projects("storage")
    handles = Enum.map(results, & &1.handle)

    assert public_match.handle in handles
    assert public_other.handle in handles
    refute "alpha-secret" in handles
  end

  test "search_projects includes private matches for organization members" do
    user = create_user("member@example.com")
    org = create_org_for_user(user, "gamma", "Gamma Org")
    other_org = create_org("delta", "Delta Org")

    _public_match =
      create_project(org, %{
        handle: "gamma-repo",
        name: "Gamma Repo",
        description: "Observability storage",
        visibility: "public"
      })

    private_match =
      create_project(org, %{
        handle: "gamma-secret",
        name: "Gamma Secret",
        description: "Private storage stack",
        visibility: "private"
      })

    _private_other =
      create_project(other_org, %{
        handle: "delta-secret",
        name: "Delta Secret",
        description: "Storage for other org",
        visibility: "private"
      })

    results = Projects.search_projects("storage", user: user)
    handles = Enum.map(results, & &1.handle)

    assert private_match.handle in handles
    refute "delta-secret" in handles
  end

  test "search_projects matches by name and trims empty queries" do
    org = create_org("epsilon", "Epsilon Org")

    match =
      create_project(org, %{
        handle: "epsilon-tools",
        name: "Epsilon Search Suite",
        description: ""
      })

    results = Projects.search_projects("  search  ")
    assert Enum.any?(results, &(&1.id == match.id))
    assert [] == Projects.search_projects("   ")
  end

  test "search_projects respects the limit option" do
    org = create_org("zeta", "Zeta Org")

    _one =
      create_project(org, %{
        handle: "zeta-omega-one",
        name: "Omega Tools",
        description: "Omega search index"
      })

    _two =
      create_project(org, %{
        handle: "zeta-omega-two",
        name: "Omega Pipeline",
        description: "Omega data flow"
      })

    results = Projects.search_projects("omega", limit: 1)

    assert length(results) == 1
  end

  defp create_user(email) do
    {:ok, user} = Accounts.get_or_create_user_by_email(email)
    user
  end

  defp create_org_for_user(user, handle, name) do
    {:ok, org} = Accounts.create_organization_for_user(user, %{handle: handle, name: name})
    org
  end

  defp create_org(handle, name) do
    {:ok, org} = Accounts.create_organization(%{handle: handle, name: name})
    org
  end

  defp create_project(org, attrs) do
    defaults = %{
      name: "Repo",
      handle: "repo-#{System.unique_integer()}",
      organization_id: org.id,
      visibility: "public"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end
end
