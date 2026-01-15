defmodule MicelioWeb.Browser.RepositoryControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Hif.{Binary, Repository, Tree}
  alias Micelio.Projects
  alias Micelio.Storage

  setup do
    {:ok, organization} = Accounts.create_organization(%{handle: "acme", name: "Acme"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "demo",
        name: "Demo",
        description: "A demo repository",
        organization_id: organization.id
      })

    readme = "# Demo\n"
    readme_hash = :crypto.hash(:sha256, readme)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, readme_hash), readme)

    app = "IO.puts(\"ok\")\n"
    app_hash = :crypto.hash(:sha256, app)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, app_hash), app)

    tree = %{"README.md" => readme_hash, "lib/app.ex" => app_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(1, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    {:ok, organization: organization, project: project}
  end

  test "shows root tree listing", %{conn: conn, organization: organization, project: project} do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"repository-tree\""
    assert html =~ "README.md"
    assert html =~ ">lib<"
  end

  test "shows directory listing", %{conn: conn, organization: organization, project: project} do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib")
    html = html_response(conn, 200)

    assert html =~ "app.ex"
  end

  test "shows file contents", %{conn: conn, organization: organization, project: project} do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/README.md")
    html = html_response(conn, 200)

    assert html =~ "id=\"repository-file-content\""
    assert html =~ "# Demo"
  end
end
