import Ecto.Changeset
# Seeds for local development
alias Micelio.Accounts.{Account, Organization, OrganizationMembership, User}
alias Micelio.Projects.Project
alias Micelio.Repo

# Create micelio user
micelio_user =
  case Repo.get_by(User, email: "micelio@micelio.dev") do
    nil ->
      {:ok, user} = Repo.insert(%User{email: "micelio@micelio.dev"})
      IO.puts("Created user: micelio@micelio.dev")
      user

    user ->
      IO.puts("User micelio@micelio.dev already exists")
      user
  end

# Create micelio organization with account
micelio_org =
  case Repo.get_by(Account, handle: "micelio") |> Repo.preload(:organization) do
    nil ->
      # Create organization
      {:ok, org} =
        %Organization{}
        |> Organization.changeset(%{name: "Micelio"})
        |> Repo.insert()

      # Create account with handle (bypassing reserved validation)
      {:ok, account} =
        %Account{}
        |> cast(%{organization_id: org.id}, [:organization_id])
        |> force_change(:handle, "micelio")
        |> unique_constraint(:handle, name: :accounts_handle_index)
        |> Repo.insert()

      IO.puts("Created organization: Micelio (@micelio)")
      %{org | account: account}

    account ->
      IO.puts("Organization @micelio already exists")
      account.organization |> Repo.preload(:account)
  end

# Create membership for micelio user as admin
case Repo.get_by(OrganizationMembership,
       user_id: micelio_user.id,
       organization_id: micelio_org.id
     ) do
  nil ->
    {:ok, _membership} =
      %OrganizationMembership{}
      |> OrganizationMembership.changeset(%{
        user_id: micelio_user.id,
        organization_id: micelio_org.id,
        role: "admin"
      })
      |> Repo.insert()

    IO.puts("Added micelio@micelio.dev as admin of Micelio org")

  _membership ->
    IO.puts("micelio@micelio.dev is already a member of Micelio org")
end

# Create micelio project
case Repo.get_by(Project, handle: "micelio", organization_id: micelio_org.id) do
  nil ->
    {:ok, _project} =
      %Project{}
      |> Project.changeset(%{
        handle: "micelio",
        name: "Micelio",
        description: "The Micelio platform",
        url: "https://micelio.dev",
        organization_id: micelio_org.id
      })
      |> Repo.insert()

    IO.puts("Created project: micelio/micelio")

  project ->
    desired = %{description: "The Micelio platform", url: "https://micelio.dev"}

    attrs =
      Enum.reduce(desired, %{}, fn {key, value}, acc ->
        if Map.get(project, key) in [nil, ""], do: Map.put(acc, key, value), else: acc
      end)

    if attrs == %{} do
      IO.puts("Project micelio/micelio already exists")
    else
      {:ok, _project} =
        project
        |> Project.changeset(attrs)
        |> Repo.update()

      IO.puts("Updated project: micelio/micelio")
    end
end

IO.puts("\nLocal development setup complete!")
IO.puts("Login with: micelio@micelio.dev")
