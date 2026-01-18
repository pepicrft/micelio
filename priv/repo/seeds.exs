# Seeds for local development
alias Micelio.Projects

case Projects.ensure_micelio_workspace() do
  {:ok, %{user: user, project: project}} ->
    IO.puts("Ensured project: micelio/micelio")
    IO.puts("\nLocal development setup complete!")
    IO.puts("Login with: #{user.email}")

    case Projects.seed_micelio_workspace_if_configured(project: project) do
      {:ok, :skipped} ->
        :ok

      {:ok, %{already_seeded: true}} ->
        IO.puts("Micelio workspace already seeded: #{project.handle}/#{project.name}")

      {:ok, %{file_count: file_count}} ->
        IO.puts(
          "Seeded Micelio workspace: #{project.handle}/#{project.name} (#{file_count} files)"
        )

      {:error, reason} ->
        raise "Failed to seed micelio workspace: #{inspect(reason)}"
    end

  {:error, reason} ->
    raise "Failed to ensure micelio workspace: #{inspect(reason)}"
end
