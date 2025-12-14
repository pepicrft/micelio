defmodule Micelio.GitTest do
  use ExUnit.Case, async: true

  describe "status/1" do
    @tag :tmp_dir
    test "returns empty list for clean repo", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.init(tmp_dir)
      assert {:ok, []} = Micelio.Git.status(tmp_dir)
    end

    @tag :tmp_dir
    test "returns untracked file", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.init(tmp_dir)
      File.write!(Path.join(tmp_dir, "test.txt"), "Hello, world!")
      assert {:ok, entries} = Micelio.Git.status(tmp_dir)
      assert [{"test.txt", "untracked"}] = entries
    end
  end

  describe "init/1" do
    @tag :tmp_dir
    test "initializes a new repository", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.init(tmp_dir)
      assert File.dir?(Path.join(tmp_dir, ".git"))
    end
  end
end
