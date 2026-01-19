defmodule Micelio.Mic.BranchProtectionTest do
  use ExUnit.Case, async: true

  alias Micelio.Mic.BranchProtection
  alias Micelio.Sessions.Session

  test "blocks protected main for common ref prefixes" do
    project = %{protect_main_branch: true}

    assert BranchProtection.blocked_main?(project, %Session{
             metadata: %{"target_branch" => "refs/heads/main"}
           })

    assert BranchProtection.blocked_main?(project, %Session{
             metadata: %{"target_branch" => "refs/remotes/origin/main"}
           })

    assert BranchProtection.blocked_main?(project, %Session{
             metadata: %{"target_branch" => "origin/main"}
           })
  end

  test "allows non-main branch when protected" do
    project = %{protect_main_branch: true}

    refute BranchProtection.blocked_main?(project, %Session{
             metadata: %{"branch" => "feature/landing"}
           })
  end
end
