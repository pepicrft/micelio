# Seeds for local development
alias Micelio.Accounts
alias Micelio.Accounts.OrganizationMembership
alias Micelio.Projects
alias Micelio.Projects.Project
alias Micelio.Repo

user_email = "test@micelio.dev"
org_handle = "micelio"
org_name = "Micelio"
project_handle = "micelio"
project_name = "Micelio"
project_description = "The Micelio platform"
project_url = "https://micelio.dev"
project_visibility = "public"

organization_result =
  case Accounts.get_organization_by_handle(org_handle) do
    {:ok, org} ->
      {:ok, org}

    {:error, :not_found} ->
      Accounts.create_organization(%{handle: org_handle, name: org_name}, allow_reserved: true)
  end

with {:ok, user} <- Accounts.get_or_create_user_by_email(user_email),
     {:ok, organization} <- organization_result do
  case Accounts.get_organization_membership(user.id, organization.id) do
    nil ->
      {:ok, _membership} =
        Accounts.create_organization_membership(%{
          user_id: user.id,
          organization_id: organization.id,
          role: :admin
        })

    %OrganizationMembership{role: :admin} ->
      :ok

    %OrganizationMembership{} = membership ->
      {:ok, _membership} =
        membership
        |> OrganizationMembership.changeset(%{role: :admin})
        |> Repo.update()
  end

  project_attrs = %{
    handle: project_handle,
    name: project_name,
    description: project_description,
    url: project_url,
    visibility: project_visibility,
    organization_id: organization.id
  }

  project =
    case Projects.get_project_by_handle(organization.id, project_handle) do
      nil ->
        case Projects.create_project(project_attrs) do
          {:ok, project} -> project
          {:error, reason} -> raise "Failed to create project: #{inspect(reason)}"
        end

      %Project{} = project ->
        update_attrs =
          Enum.reduce([:name, :description, :url], %{}, fn key, acc ->
            value = Map.get(project, key)
            desired = Map.get(project_attrs, key)

            if value in [nil, ""], do: Map.put(acc, key, desired), else: acc
          end)

        update_attrs =
          if project.visibility == project_visibility do
            update_attrs
          else
            Map.put(update_attrs, :visibility, project_visibility)
          end

        if update_attrs == %{} do
          project
        else
          case Projects.update_project_settings(project, update_attrs) do
            {:ok, project} -> project
            {:error, reason} -> raise "Failed to update project: #{inspect(reason)}"
          end
        end
    end

  IO.puts("Ensured project: #{org_handle}/#{project.handle}")
  IO.puts("\nLocal development setup complete!")
  IO.puts("Login with: #{user.email}")

  case Projects.seed_micelio_workspace_if_configured(project: project) do
    {:ok, :skipped} ->
      :ok

    {:ok, %{already_seeded: true}} ->
      IO.puts("Micelio workspace already seeded: #{project.handle}/#{project.name}")

    {:ok, %{file_count: file_count}} ->
      IO.puts("Seeded Micelio workspace: #{project.handle}/#{project.name} (#{file_count} files)")

    {:error, reason} ->
      raise "Failed to seed micelio workspace: #{inspect(reason)}"
  end
else
  {:error, reason} ->
    raise "Failed to ensure Micelio seed data: #{inspect(reason)}"
end
