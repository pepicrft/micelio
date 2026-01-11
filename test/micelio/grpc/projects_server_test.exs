defmodule Micelio.GRPC.ProjectsServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Projects.V1.{
    CreateProjectRequest,
    DeleteProjectRequest,
    GetProjectRequest,
    ListProjectsRequest,
    ListProjectsResponse,
    ProjectResponse,
    UpdateProjectRequest
  }
  alias Micelio.GRPC.Projects.V1.ProjectService.Server
  alias Micelio.Projects

  test "list_projects returns projects for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-list@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-org",
        name: "GRPC Org"
      })

    {:ok, _} =
      Projects.create_project(%{
        handle: "grpc-project",
        name: "GRPC Project",
        organization_id: organization.id
      })

    response =
      Server.list_projects(
        %ListProjectsRequest{
          user_id: user.id,
          organization_handle: organization.account.handle
        },
        nil
      )

    assert %ListProjectsResponse{} = response
    assert length(response.projects) == 1
  end

  test "create_project rejects unauthorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-owner@example.com")
    {:ok, other_user} = Accounts.get_or_create_user_by_email("grpc-guest@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-owner-org",
        name: "GRPC Owner Org"
      })

    response =
      Server.create_project(
        %CreateProjectRequest{
          user_id: other_user.id,
          organization_handle: organization.account.handle,
          handle: "blocked-project",
          name: "Blocked Project",
          description: ""
        },
        nil
      )

    assert {:error, _} = response
  end

  test "update_project returns updated project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-update@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-update-org",
        name: "GRPC Update Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-update-project",
        name: "GRPC Update Project",
        organization_id: organization.id
      })

    response =
      Server.update_project(
        %UpdateProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: project.handle,
          new_handle: "grpc-updated",
          name: "Updated",
          description: "Updated"
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.project.handle == "grpc-updated"
  end

  test "delete_project removes project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-delete@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-delete-org",
        name: "GRPC Delete Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-delete-project",
        name: "GRPC Delete Project",
        organization_id: organization.id
      })

    response =
      Server.delete_project(
        %DeleteProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: project.handle
        },
        nil
      )

    assert %{success: true} = response
    assert Projects.get_project(project.id) == nil
  end

  test "get_project returns project for authorized user" do
    {:ok, user} = Accounts.get_or_create_user_by_email("grpc-get@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "grpc-get-org",
        name: "GRPC Get Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "grpc-get-project",
        name: "GRPC Get Project",
        organization_id: organization.id
      })

    response =
      Server.get_project(
        %GetProjectRequest{
          user_id: user.id,
          organization_handle: organization.account.handle,
          handle: project.handle
        },
        nil
      )

    assert %ProjectResponse{} = response
    assert response.project.id == project.id
  end
end
