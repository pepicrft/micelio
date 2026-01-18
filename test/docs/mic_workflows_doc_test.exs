defmodule Micelio.Docs.MicWorkflowsDocTest do
  use ExUnit.Case, async: true

  test "mic workflows documentation includes core commands" do
    path = Path.expand("../../docs/users/mic-workflows.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(contents, "# mic Workflows")
    assert String.contains?(contents, "mic auth login")
    assert String.contains?(contents, "mic checkout")
    assert String.contains?(contents, "mic session start")
    assert String.contains?(contents, "mic session land")
    assert String.contains?(contents, "mic mount")
  end
end
