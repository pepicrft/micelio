# Seeds for local development
alias Micelio.Projects

case Projects.ensure_micelio_workspace() do
  {:ok, %{user: user}} ->
    IO.puts("Ensured project: micelio/micelio")
    IO.puts("\nLocal development setup complete!")
    IO.puts("Login with: #{user.email}")

  {:error, reason} ->
    raise "Failed to ensure micelio workspace: #{inspect(reason)}"
end
