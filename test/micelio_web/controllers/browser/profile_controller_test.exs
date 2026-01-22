defmodule MicelioWeb.Browser.ProfileControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Storage

  defmodule SuccessValidator do
    def validate(_config), do: {:ok, %{ok?: true, errors: []}}
  end

  setup :register_and_log_in_user
  setup :use_success_validator

  defp use_success_validator(_) do
    previous = Application.get_env(:micelio, Storage)

    Application.put_env(:micelio, Storage, s3_validator: SuccessValidator)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Storage)
        _ -> Application.put_env(:micelio, Storage, previous)
      end
    end)

    :ok
  end

  test "shows profile page with devices link", %{conn: conn, user: user} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "@#{user.account.handle}"
    assert html =~ "id=\"account-devices-link\""
  end

  test "shows navbar user link on authenticated pages", %{conn: conn, user: _user} do
    conn = get(conn, ~p"/account/devices")
    html = html_response(conn, 200)

    assert html =~ "class=\"navbar-user-avatar\""
    assert html =~ "id=\"navbar-user\""
    assert html =~ "href=\"/account\""
    assert html =~ "gravatar.com/avatar/"
  end

  test "shows favorites list for starred projects", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization(%{handle: "favorite-org", name: "Favorite Org"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "favorite-project",
        name: "Favorite Project",
        organization_id: organization.id,
        visibility: "public"
      })

    assert {:ok, _star} = Projects.star_project(user, project)

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-favorites\""
    assert html =~ "id=\"account-favorites-list\""
    assert html =~ "favorite-#{project.id}"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
  end

  test "shows owned projects list for admin organizations", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "owned-org",
        name: "Owned Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "owned-project",
        name: "Owned Project",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-owned-projects\""
    assert html =~ "id=\"account-owned-projects-list\""
    assert html =~ "owned-project-#{project.id}"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
  end

  test "shows organizations list for memberships", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "team-org",
        name: "Team Org"
      })

    {:ok, other_user} = Accounts.get_or_create_user_by_email("member@example.com")

    assert {:ok, _membership} =
             Accounts.create_organization_membership(%{
               user_id: other_user.id,
               organization_id: organization.id,
               role: "user"
             })

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-organizations\""
    assert html =~ "id=\"account-organizations-list\""
    assert html =~ "organization-#{organization.id}"
    assert html =~ organization.name
    assert html =~ "@#{organization.account.handle}"
    assert html =~ "2 members"
  end

  test "shows activity graph for landed sessions", %{conn: conn, user: user} do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "activity-org",
        name: "Activity Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "activity-project",
        name: "Activity Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "activity-session",
        goal: "Ship activity",
        project_id: project.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(session)

    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-activity\""
    assert html =~ "class=\"account-section-title\">Activity"
    assert html =~ "activity-graph"
    assert html =~ "aria-label=\"1 contributions\""
    assert html =~ "activity-graph-legend"
  end

  test "shows storage section with S3 form", %{conn: conn} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "id=\"account-storage\""
    assert html =~ "id=\"account-storage-settings\""
  end

  test "saves S3 configuration", %{conn: conn, user: user} do
    params = %{
      "provider" => "aws_s3",
      "bucket_name" => "user-bucket",
      "region" => "us-east-1",
      "endpoint_url" => "",
      "access_key_id" => "access-key",
      "secret_access_key" => "secret-key",
      "path_prefix" => "sessions/"
    }

    conn = patch(conn, ~p"/account/storage/s3", %{"s3_config" => params})

    assert redirected_to(conn) == ~p"/settings/storage"
    assert get_flash(conn, :info) =~ "S3 configuration saved"

    config = Storage.get_user_s3_config(user)
    assert config.bucket_name == "user-bucket"
    assert config.provider == :aws_s3
    assert config.validated_at
  end
end
