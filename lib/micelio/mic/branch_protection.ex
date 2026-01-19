defmodule Micelio.Mic.BranchProtection do
  @moduledoc false

  alias Micelio.Sessions.Session

  def blocked_main?(%{protect_main_branch: true}, %Session{} = session) do
    target_branch(session, nil) == "main"
  end

  def blocked_main?(_project, _session), do: false

  def blocked_main?(%{protect_main_branch: true}, %Session{} = session, target_branch_override) do
    target_branch(session, target_branch_override) == "main"
  end

  def blocked_main?(_project, _session, _target_branch_override), do: false

  def target_branch(%Session{}, target_branch_override)
      when is_binary(target_branch_override) and target_branch_override != "" do
    target_branch_override
    |> normalize_branch()
  end

  def target_branch(%Session{metadata: %{} = metadata}, _target_branch_override) do
    metadata
    |> extract_target_branch()
    |> normalize_branch()
  end

  def target_branch(%Session{}, _target_branch_override), do: "main"

  defp extract_target_branch(%{"target_branch" => branch})
       when is_binary(branch) and branch != "" do
    branch
  end

  defp extract_target_branch(%{"branch" => branch}) when is_binary(branch) and branch != "" do
    branch
  end

  defp extract_target_branch(_metadata), do: "main"

  defp normalize_branch(branch) when is_binary(branch) do
    branch
    |> String.trim()
    |> String.replace_prefix("refs/heads/", "")
    |> String.replace_prefix("refs/remotes/", "")
    |> String.replace_prefix("origin/", "")
  end
end
