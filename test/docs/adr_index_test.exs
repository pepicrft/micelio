defmodule Micelio.Docs.AdrIndexTest do
  use ExUnit.Case, async: true

  test "ADR index lists core decisions" do
    path = Path.expand("../../docs/adr/README.md", __DIR__)
    contents = File.read!(path)

    assert String.contains?(contents, "# Architecture Decision Records")
    assert String.contains?(contents, "0001-agent-first-session-workflows")
    assert String.contains?(contents, "0002-tiered-storage-caching")
    assert String.contains?(contents, "0003-activitypub-federation")
  end

  test "ADR files exist" do
    adr_dir = Path.expand("../../docs/adr", __DIR__)

    assert File.exists?(Path.join(adr_dir, "0001-agent-first-session-workflows.md"))
    assert File.exists?(Path.join(adr_dir, "0002-tiered-storage-caching.md"))
    assert File.exists?(Path.join(adr_dir, "0003-activitypub-federation.md"))
  end
end
