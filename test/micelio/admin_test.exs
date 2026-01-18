defmodule Micelio.AdminTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts.User
  alias Micelio.Admin
  alias Micelio.Repo
  alias Micelio.{Accounts, Projects, Sessions}

  describe "admin access" do
    test "admin_emails/0 returns configured emails normalized to lowercase" do
      assert Admin.admin_emails() == ["admin@example.com"]
    end

    test "admin_user?/1 matches configured emails case-insensitively" do
      assert Admin.admin_user?(%User{email: "ADMIN@EXAMPLE.COM"})
      refute Admin.admin_user?(%User{email: "member@example.com"})
    end
  end

  describe "admin dashboard queries" do
    test "dashboard_stats/0 returns aggregate counts" do
      {:ok, user1} = Accounts.get_or_create_user_by_email("admin@example.com")
      {:ok, _user2} = Accounts.get_or_create_user_by_email("member@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user1, %{name: "Acme", handle: "acme"})

      {:ok, project} =
        Projects.create_project(%{
          name: "Acme Repo",
          handle: "acme-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_project} =
        Projects.create_project(%{
          name: "Acme Private",
          handle: "acme-private",
          organization_id: organization.id,
          visibility: "private"
        })

      {:ok, _session} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Ship overview",
          project_id: project.id,
          user_id: user1.id
        })

      stats = Admin.dashboard_stats()

      assert stats.users == 2
      assert stats.admin_emails_configured == 1
      assert stats.admin_users == 1
      assert stats.organizations == 1
      assert stats.projects == 2
      assert stats.sessions == 1
      assert stats.public_projects == 1
      assert stats.private_projects == 1
    end

    test "list_recent_users/1 returns users in reverse chronological order" do
      {:ok, older} = Accounts.get_or_create_user_by_email("older@example.com")
      {:ok, newer} = Accounts.get_or_create_user_by_email("newer@example.com")

      older = set_inserted_at(older, ~N[2024-01-01 00:00:00])
      newer = set_inserted_at(newer, ~N[2024-01-02 00:00:00])

      recent_users = Admin.list_recent_users(2)

      assert Enum.map(recent_users, & &1.id) == [newer.id, older.id]
      assert Enum.all?(recent_users, fn user -> user.account.handle != "" end)
    end

    test "list_recent_organizations/1 returns organizations in reverse chronological order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("org_admin@example.com")

      {:ok, older_org} =
        Accounts.create_organization_for_user(user, %{name: "Older Org", handle: "older-org"})

      {:ok, newer_org} =
        Accounts.create_organization_for_user(user, %{name: "Newer Org", handle: "newer-org"})

      older_org = set_inserted_at(older_org, ~N[2024-01-01 00:00:00])
      newer_org = set_inserted_at(newer_org, ~N[2024-01-02 00:00:00])

      recent_orgs = Admin.list_recent_organizations(2)

      assert Enum.map(recent_orgs, & &1.id) == [newer_org.id, older_org.id]
      assert Enum.all?(recent_orgs, fn org -> org.account.handle != "" end)
    end

    test "list_recent_projects/1 returns projects in reverse chronological order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("project_admin@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{name: "Acme", handle: "acme"})

      {:ok, older_project} =
        Projects.create_project(%{
          name: "Older Repo",
          handle: "older-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, newer_project} =
        Projects.create_project(%{
          name: "Newer Repo",
          handle: "newer-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      older_project = set_inserted_at(older_project, ~N[2024-01-01 00:00:00])
      newer_project = set_inserted_at(newer_project, ~N[2024-01-02 00:00:00])

      recent_projects = Admin.list_recent_projects(2)

      assert Enum.map(recent_projects, & &1.id) == [newer_project.id, older_project.id]

      assert Enum.all?(recent_projects, fn project ->
               project.organization.account.handle != ""
             end)
    end

    test "list_recent_sessions/1 preloads related data in reverse order" do
      {:ok, user} = Accounts.get_or_create_user_by_email("user@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{name: "Acme", handle: "acme"})

      {:ok, project} =
        Projects.create_project(%{
          name: "Acme Repo",
          handle: "acme-repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, older_session} =
        Sessions.create_session(%{
          session_id: "session-older",
          goal: "Older",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, newer_session} =
        Sessions.create_session(%{
          session_id: "session-newer",
          goal: "Newer",
          project_id: project.id,
          user_id: user.id
        })

      older_session = set_inserted_at(older_session, ~N[2024-01-01 00:00:00])
      newer_session = set_inserted_at(newer_session, ~N[2024-01-02 00:00:00])

      recent_sessions = Admin.list_recent_sessions(2)

      assert Enum.map(recent_sessions, & &1.id) == [newer_session.id, older_session.id]

      assert Enum.all?(recent_sessions, fn session ->
               session.user.email != "" and
                 session.project.organization.account.handle != ""
             end)
    end
  end

  defp set_inserted_at(struct, inserted_at) do
    inserted_at =
      case {struct.__struct__.__schema__(:type, :inserted_at), inserted_at} do
        {:utc_datetime, %NaiveDateTime{} = naive} -> DateTime.from_naive!(naive, "Etc/UTC")
        {:naive_datetime, %DateTime{} = datetime} -> DateTime.to_naive(datetime)
        {_type, value} -> value
      end

    struct
    |> Ecto.Changeset.change(%{inserted_at: inserted_at, updated_at: inserted_at})
    |> Repo.update!()
  end
end
