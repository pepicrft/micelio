defmodule Micelio.GitTest do
  use ExUnit.Case, async: true

  describe "status/1" do
    @tag :tmp_dir
    test "returns empty list for clean repo", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.repository_init(tmp_dir)
      assert {:ok, []} = Micelio.Git.status(tmp_dir)
    end

    @tag :tmp_dir
    test "returns untracked file", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.repository_init(tmp_dir)
      File.write!(Path.join(tmp_dir, "test.txt"), "Hello, world!")
      assert {:ok, entries} = Micelio.Git.status(tmp_dir)
      assert [{"test.txt", "untracked"}] = entries
    end

    @tag :tmp_dir
    test "returns error when path is not a git repository", %{tmp_dir: tmp_dir} do
      assert {:error, :repository_not_found} = Micelio.Git.status(tmp_dir)
    end

    test "returns error when path does not exist" do
      assert {:error, :repository_not_found} = Micelio.Git.status("/nonexistent/path")
    end
  end

  describe "repository_init/1" do
    @tag :tmp_dir
    test "initializes a new repository", %{tmp_dir: tmp_dir} do
      assert :ok = Micelio.Git.repository_init(tmp_dir)
      assert File.dir?(Path.join(tmp_dir, ".git"))
    end

    test "returns error when path does not exist" do
      assert {:error, :repository_init_failed} =
               Micelio.Git.repository_init("/nonexistent/path/to/repo")
    end
  end

  describe "repository_default_branch/1" do
    @tag :tmp_dir
    test "returns the default branch name", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      # Create initial commit so HEAD points to a branch
      readme = Path.join(tmp_dir, "README.md")
      File.write!(readme, "# Test")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:ok, branch} = Micelio.Git.repository_default_branch(tmp_dir)
      assert branch in ["main", "master"]
    end

    test "returns error when path is not a repository" do
      assert {:error, :repository_not_found} =
               Micelio.Git.repository_default_branch("/nonexistent")
    end

    @tag :tmp_dir
    test "returns error when repository has no commits", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      assert {:error, :head_not_found} = Micelio.Git.repository_default_branch(tmp_dir)
    end
  end

  describe "tree_list/3" do
    @tag :tmp_dir
    test "lists files at root", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.write!(Path.join(tmp_dir, "README.md"), "# Test")
      File.mkdir_p!(Path.join(tmp_dir, "src"))
      File.write!(Path.join(tmp_dir, "src/main.ex"), "defmodule Main do end")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:ok, entries} = Micelio.Git.tree_list(tmp_dir, "HEAD", "")

      names = Enum.map(entries, fn {name, _type, _oid} -> name end)
      assert "README.md" in names
      assert "src" in names

      readme_entry = Enum.find(entries, fn {name, _, _} -> name == "README.md" end)
      assert {"README.md", "blob", _oid} = readme_entry

      src_entry = Enum.find(entries, fn {name, _, _} -> name == "src" end)
      assert {"src", "tree", _oid} = src_entry
    end

    @tag :tmp_dir
    test "lists files in subdirectory", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.mkdir_p!(Path.join(tmp_dir, "src"))
      File.write!(Path.join(tmp_dir, "src/main.ex"), "defmodule Main do end")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:ok, entries} = Micelio.Git.tree_list(tmp_dir, "HEAD", "src")
      assert [{"main.ex", "blob", _oid}] = entries
    end

    test "returns error for nonexistent ref" do
      assert {:error, :ref_not_found} = Micelio.Git.tree_list(".", "nonexistent-branch", "")
    end

    @tag :tmp_dir
    test "returns error for nonexistent path", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.write!(Path.join(tmp_dir, "README.md"), "# Test")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:error, :path_not_found} = Micelio.Git.tree_list(tmp_dir, "HEAD", "nonexistent")
    end
  end

  describe "tree_blob/3" do
    @tag :tmp_dir
    test "reads file content", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.write!(Path.join(tmp_dir, "README.md"), "# Hello World")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:ok, content} = Micelio.Git.tree_blob(tmp_dir, "HEAD", "README.md")
      assert content == "# Hello World"
    end

    @tag :tmp_dir
    test "reads file in subdirectory", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule App do end")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:ok, content} = Micelio.Git.tree_blob(tmp_dir, "HEAD", "lib/app.ex")
      assert content == "defmodule App do end"
    end

    test "returns error for nonexistent file" do
      assert {:error, :file_not_found} = Micelio.Git.tree_blob(".", "HEAD", "nonexistent.txt")
    end

    @tag :tmp_dir
    test "returns error when path is a directory", %{tmp_dir: tmp_dir} do
      :ok = Micelio.Git.repository_init(tmp_dir)
      File.mkdir_p!(Path.join(tmp_dir, "src"))
      File.write!(Path.join(tmp_dir, "src/main.ex"), "defmodule Main do end")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "Initial commit"])

      assert {:error, :not_a_file} = Micelio.Git.tree_blob(tmp_dir, "HEAD", "src")
    end
  end
end
