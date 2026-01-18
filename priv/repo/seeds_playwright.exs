alias Micelio.Accounts
alias Micelio.Accounts.Organization
alias Micelio.Mic.{Binary, Repository, Tree}
alias Micelio.Projects
alias Micelio.Repo
alias Micelio.Storage

org_handle = "playwright"
org_name = "Playwright Org"
project_handle = "mobile-layout"
project_name = "Mobile Layout"
project_description = "Sample project for mobile layout checks."

organization =
  Repo.get_by(Organization, name: org_name) ||
    case %Organization{}
         |> Organization.changeset(%{name: org_name})
         |> Repo.insert() do
      {:ok, org} ->
        org

      {:error, changeset} ->
        raise "Failed to create organization: #{inspect(changeset.errors)}"
    end

account =
  case Accounts.get_account_by_handle(org_handle) do
    nil ->
      case Accounts.create_organization_account(%{
             handle: org_handle,
             organization_id: organization.id
           }) do
        {:ok, account} ->
          account

        {:error, changeset} ->
          raise "Failed to create organization account: #{inspect(changeset.errors)}"
      end

    %{organization_id: ^organization.id} = account ->
      account

    %{organization_id: other_org} ->
      raise "Account #{org_handle} belongs to a different organization: #{other_org}"

    %{user_id: _user_id} ->
      raise "Account #{org_handle} is a user account, expected organization"
  end

project =
  case Projects.get_project_by_handle(organization.id, project_handle) do
    nil ->
      case Projects.create_project(%{
             handle: project_handle,
             name: project_name,
             description: project_description,
             organization_id: organization.id,
             visibility: "public"
           }) do
        {:ok, project} ->
          project

        {:error, changeset} ->
          raise "Failed to create project: #{inspect(changeset.errors)}"
      end

    project ->
      {:ok, updated} =
        Projects.update_project(project, %{
          name: project_name,
          description: project_description,
          visibility: "public"
        })

      updated
  end

readme = "# Mobile Layout\n"
readme_hash = :crypto.hash(:sha256, readme)
{:ok, _} = Storage.put(Repository.blob_key(project.id, readme_hash), readme)

app = "IO.puts(\"hello from mobile\")\n"
app_hash = :crypto.hash(:sha256, app)
{:ok, _} = Storage.put(Repository.blob_key(project.id, app_hash), app)

tree = %{"README.md" => readme_hash, "lib/app.ex" => app_hash}
encoded_tree = Tree.encode(tree)
tree_hash = Tree.hash(encoded_tree)
{:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

head = Binary.new_head(1, tree_hash)
{:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

IO.puts("Seeded Playwright fixtures: #{account.handle}/#{project.handle}")
