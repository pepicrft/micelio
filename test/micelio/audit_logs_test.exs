defmodule Micelio.AuditLogsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AuditLog
  alias Micelio.Projects
  alias Micelio.Repo
  alias Micelio.Webhooks

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("audit@example.com")

    {:ok, organization} =
      Accounts.create_organization(%{handle: "audit-org", name: "Audit Org"})

    %{user: user, organization: organization}
  end

  test "logs project creation", %{user: user, organization: organization} do
    attrs = %{handle: "audit-project", name: "Audit Project", organization_id: organization.id}

    assert {:ok, project} = Projects.create_project(attrs, user: user)

    log = Repo.get_by(AuditLog, project_id: project.id, action: "project.created")

    assert log.user_id == user.id
    assert log.metadata["handle"] == "audit-project"
    assert log.metadata["organization_id"] == organization.id
  end

  test "logs project settings updates with changes", %{user: user, organization: organization} do
    {:ok, project} =
      Projects.create_project(
        %{handle: "audit-settings", name: "Audit Settings", organization_id: organization.id},
        user: user
      )

    assert {:ok, _updated} =
             Projects.update_project_settings(project, %{visibility: "public"}, user: user)

    log =
      Repo.get_by(AuditLog,
        project_id: project.id,
        action: "project.settings_updated"
      )

    assert log.metadata["changes"]["visibility"] == "public"
  end

  test "logs project deletion", %{user: user, organization: organization} do
    {:ok, project} =
      Projects.create_project(
        %{handle: "audit-delete", name: "Audit Delete", organization_id: organization.id},
        user: user
      )

    assert {:ok, _deleted} = Projects.delete_project(project, user: user)

    log = Repo.get_by(AuditLog, project_id: project.id, action: "project.deleted")

    assert log.metadata["handle"] == "audit-delete"
    assert log.metadata["organization_id"] == organization.id
  end

  test "logs webhook creation without secrets", %{user: user, organization: organization} do
    {:ok, project} =
      Projects.create_project(
        %{handle: "audit-hook", name: "Audit Hook", organization_id: organization.id},
        user: user
      )

    assert {:ok, webhook} =
             Webhooks.create_webhook(
               %{
                 project_id: project.id,
                 url: "https://hooks.example.com/push",
                 events: ["push"],
                 secret: "super-secret"
               },
               user: user
             )

    log = Repo.get_by(AuditLog, project_id: project.id, action: "webhook.created")

    assert log.metadata["webhook_id"] == webhook.id
    assert log.metadata["url"] == webhook.url
    refute Map.has_key?(log.metadata, "secret")
    refute Map.has_key?(log.metadata["changes"], "secret")
  end
end
