defmodule MicelioWeb.Browser.RepositoryControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.Mic.{Binary, Repository, Tree}
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Storage
  alias Plug.CSRFProtection

  setup do
    {:ok, organization} = Accounts.create_organization(%{handle: "acme", name: "Acme"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "demo",
        name: "Demo",
        description: "A demo repository",
        organization_id: organization.id,
        visibility: "public"
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

    assert html =~ "id=\"project-tree\""
    assert html =~ "id=\"project-breadcrumb\""
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/blob/README.md"
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/tree/lib"
    assert html =~ "README.md"
    assert html =~ ">lib<"
    refute html =~ "id=\"project-tree-parent\""

    lib_index = :binary.match(html, "project-tree-name\">lib<")
    readme_index = :binary.match(html, "project-tree-name\">README.md<")

    assert match?({_, _}, lib_index)
    assert match?({_, _}, readme_index)
    assert elem(lib_index, 0) < elem(readme_index, 0)
  end

  test "shows agent progress link on repository page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-agents-link\""
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/agents"
  end

  test "labels directory and file entries in the tree", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    doc = LazyHTML.from_fragment(html)
    kinds_text = doc |> LazyHTML.query(".project-tree-kind") |> LazyHTML.text()

    assert String.contains?(kinds_text, "dir")
    assert String.contains?(kinds_text, "file")
  end

  test "renders README on repository homepage", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-readme\""
    assert html =~ "id=\"project-readme-content\""
    assert html =~ "<h1>"
    assert html =~ "Demo"
  end

  test "renders plaintext README on repository homepage", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    readme = "Plain README\n"
    readme_hash = :crypto.hash(:sha256, readme)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, readme_hash), readme)

    tree = %{"README.txt" => readme_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(2, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-readme\""
    assert html =~ "class=\"project-readme-content\""
    assert html =~ "Plain README"
  end

  test "renders binary README notice on repository homepage", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    readme = <<0xFF, 0xD8, 0xFF>>
    readme_hash = :crypto.hash(:sha256, readme)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, readme_hash), readme)

    tree = %{"README" => readme_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(3, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-readme\""
    assert html =~ "class=\"project-readme-binary\""
    assert html =~ "Binary file (3 bytes) cannot be displayed."
  end

  test "serves an embeddable badge for public repositories", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/badge.svg")
    body = response(conn, 200)

    assert body =~ "<svg"
    assert body =~ "#{organization.account.handle}/#{project.handle}"
    assert body =~ "0 stars"
    assert List.first(get_resp_header(conn, "content-type")) =~ "image/svg+xml"
  end

  test "shows embeddable badge snippets on the repository page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-badge\""
    assert html =~ "/#{organization.account.handle}/#{project.handle}/badge.svg"
    assert html =~ "[![#{organization.account.handle}/#{project.handle}]("
    assert html =~ "id=\"project-badge-markdown\""
    assert html =~ "id=\"project-badge-html\""
  end

  test "allows contributing tokens to a project", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: _user} = register_and_log_in_user(%{conn: conn})
    return_to = ~p"/#{organization.account.handle}/#{project.handle}"

    conn =
      conn
      |> with_csrf()
      |> post(~p"/#{organization.account.handle}/#{project.handle}/token-contributions", %{
        "token_contribution" => %{"amount" => "15", "return_to" => return_to}
      })

    assert redirected_to(conn) == return_to
    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Thanks for contributing tokens to this project."

    pool = AITokens.get_token_pool_by_project(project.id)
    assert pool.balance == 15
  end

  test "returns not found for badges on private repositories", %{
    conn: conn,
    organization: organization
  } do
    {:ok, private_project} =
      Projects.create_project(%{
        handle: "secret",
        name: "Secret",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/#{organization.account.handle}/#{private_project.handle}/badge.svg")

    assert response(conn, 404)
  end

  test "shows directory listing", %{conn: conn, organization: organization, project: project} do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib")
    html = html_response(conn, 200)

    assert html =~ "app.ex"
    assert html =~ "id=\"project-breadcrumb\""
    assert html =~ "class=\"project-breadcrumb-current\">lib"
    assert html =~ "/#{organization.account.handle}/#{project.handle}/tree/lib"
    assert html =~ "id=\"project-tree-parent\""
  end

  test "normalizes trailing slashes in tree paths", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib/")
    html = html_response(conn, 200)

    assert html =~ "class=\"project-breadcrumb-current\">lib"
    assert html =~ "id=\"project-tree-parent\""
  end

  test "links parent directory to repository root for first-level paths", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-tree-parent\""
    assert html =~ "href=\"/#{organization.account.handle}/#{project.handle}\""
  end

  test "navigates nested directories", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    app = "IO.puts(\"ok\")\n"
    app_hash = :crypto.hash(:sha256, app)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, app_hash), app)

    helpers = "defmodule Helpers do\nend\n"
    helpers_hash = :crypto.hash(:sha256, helpers)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, helpers_hash), helpers)

    tree = %{"lib/app.ex" => app_hash, "lib/utils/helpers.ex" => helpers_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(5, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib")
    html = html_response(conn, 200)

    assert html =~ "utils"
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/tree/lib/utils"

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib/utils")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-breadcrumb\""
    assert html =~ "class=\"project-breadcrumb-current\">utils"
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/tree/lib"
    assert html =~ "helpers.ex"
    assert html =~ "id=\"project-tree-parent\""
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/tree/lib"
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/blob/lib/utils/helpers.ex"
  end

  test "shows empty state for repositories without any files", %{
    conn: conn,
    organization: organization
  } do
    {:ok, empty_project} =
      Projects.create_project(%{
        handle: "empty-repo",
        name: "Empty Repo",
        organization_id: organization.id,
        visibility: "public"
      })

    conn = get(conn, ~p"/#{organization.account.handle}/#{empty_project.handle}")
    html = html_response(conn, 200)

    assert html =~ "No files yet"
    assert html =~ "class=\"project-empty\""
  end

  test "shows file contents", %{conn: conn, organization: organization, project: project} do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/README.md")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-file-content\""
    assert html =~ "# Demo"
  end

  test "shows blame view with unknown attribution when no landed sessions", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blame/lib/app.ex")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-blame-table\""
    assert html =~ "project-blame-line-1"
    assert html =~ "unknown"
  end

  test "shows blame view with session attribution", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, user_one} = Accounts.get_or_create_user_by_email("alice@example.com")
    {:ok, user_two} = Accounts.get_or_create_user_by_email("bob@example.com")

    base_content = "IO.puts(\"ok\")\n"
    updated_content = ~s{IO.puts("ok")\nIO.puts("next")\n}

    updated_hash = :crypto.hash(:sha256, updated_content)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, updated_hash), updated_content)

    tree = %{"lib/app.ex" => updated_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(6, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    {:ok, session_one} =
      Sessions.create_session(%{
        session_id: "session-one",
        goal: "Initial import",
        project_id: project.id,
        user_id: user_one.id
      })

    {:ok, _} =
      Sessions.create_session_change(%{
        session_id: session_one.id,
        file_path: "lib/app.ex",
        change_type: "added",
        content: base_content
      })

    {:ok, session_one} = Sessions.land_session(session_one)

    {:ok, _} =
      Sessions.update_session(session_one, %{
        landed_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, session_two} =
      Sessions.create_session(%{
        session_id: "session-two",
        goal: "Add follow-up output",
        project_id: project.id,
        user_id: user_two.id
      })

    {:ok, _} =
      Sessions.create_session_change(%{
        session_id: session_two.id,
        file_path: "lib/app.ex",
        change_type: "modified",
        content: updated_content
      })

    {:ok, session_two} = Sessions.land_session(session_two)

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blame/lib/app.ex")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-blame-table\""
    assert html =~ "project-blame-line-1"
    assert html =~ "project-blame-line-2"
    assert html =~ session_one.session_id
    assert html =~ session_two.session_id
    assert html =~ user_one.account.handle
    assert html =~ user_two.account.handle
  end

  test "shows binary blame notice for binary files", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    binary = <<0xFF, 0xD8, 0xFF, 0xE0>>
    binary_hash = :crypto.hash(:sha256, binary)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, binary_hash), binary)

    tree = %{"bin/image.jpg" => binary_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(7, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blame/bin/image.jpg")
    html = html_response(conn, 200)

    assert html =~ "class=\"project-file-binary\""
    assert html =~ "Binary file (4 bytes) cannot be blamed."
  end

  test "shows breadcrumb navigation for files", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/lib/app.ex")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-breadcrumb\""
    assert html =~ ~p"/#{organization.account.handle}/#{project.handle}/tree/lib"
    assert html =~ "app.ex"
  end

  test "redirects tree file paths to blob view", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/README.md")

    assert redirected_to(conn) ==
             ~p"/#{organization.account.handle}/#{project.handle}/blob/README.md"
  end

  test "redirects nested tree file paths to blob view", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/lib/app.ex")

    assert redirected_to(conn) ==
             ~p"/#{organization.account.handle}/#{project.handle}/blob/lib/app.ex"
  end

  test "returns not found for missing tree paths", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/tree/missing")

    assert response(conn, 404) =~ "Not found"
  end

  test "highlights code files with known lexers", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/lib/app.ex")
    html = html_response(conn, 200)

    assert html =~ "class=\"project-file-content highlight\""
    assert html =~ "<span class=\""
    assert html =~ "ok"
  end

  test "renders plaintext for files without a known lexer", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    notes = "Plain notes\n"
    notes_hash = :crypto.hash(:sha256, notes)
    {:ok, _} = Storage.put(Repository.blob_key(project.id, notes_hash), notes)

    tree = %{"notes.txt" => notes_hash}
    encoded_tree = Tree.encode(tree)
    tree_hash = Tree.hash(encoded_tree)
    {:ok, _} = Storage.put(Repository.tree_key(project.id, tree_hash), encoded_tree)

    head = Binary.new_head(4, tree_hash)
    {:ok, _} = Storage.put(Repository.head_key(project.id), Binary.encode_head(head))

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/notes.txt")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-file-content\""
    refute html =~ "project-file-content highlight"
    assert html =~ "Plain notes"
  end

  test "shows CDN download link for blobs when configured", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Configure CDN via process dictionary (no global state!)
    Process.put(:micelio_storage_config, cdn_base_url: "https://cdn.example.test/micelio")

    on_exit(fn ->
      Process.delete(:micelio_storage_config)
    end)

    app = "IO.puts(\"ok\")\n"
    app_hash = :crypto.hash(:sha256, app)
    key = Repository.blob_key(project.id, app_hash)

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}/blob/lib/app.ex")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-blob-download\""
    assert html =~ "https://cdn.example.test/micelio/#{key}"
  end

  test "shows star action and count for authenticated users", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-star-toggle\""
    assert html =~ "Stars: 0"
  end

  test "hides star action for unauthenticated users", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    refute html =~ "id=\"project-star-toggle\""
    assert html =~ "Stars: 0"
  end

  test "toggles stars on a repository", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})
    path = ~p"/#{organization.account.handle}/#{project.handle}"

    conn =
      conn
      |> with_csrf()
      |> post(~p"/#{organization.account.handle}/#{project.handle}/star", %{
        "star" => %{"return_to" => path}
      })

    assert redirected_to(conn) == path
    assert Projects.project_starred?(user, project)
    assert Projects.count_project_stars(project) == 1

    conn =
      conn
      |> recycle()
      |> with_csrf()
      |> post(~p"/#{organization.account.handle}/#{project.handle}/star", %{
        "star" => %{"return_to" => path}
      })

    assert redirected_to(conn) == path
    refute Projects.project_starred?(user, project)
    assert Projects.count_project_stars(project) == 0
  end

  test "shows fork action for organization admins", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    {:ok, target_org} =
      Accounts.create_organization(%{handle: "fork-target", name: "Fork Target"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: user.id,
        organization_id: target_org.id,
        role: "admin"
      })

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    assert html =~ "id=\"project-fork-form\""
    assert html =~ "id=\"project-fork-submit\""
  end

  test "hides fork action for users without admin organizations", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    {:ok, target_org} =
      Accounts.create_organization(%{handle: "fork-member", name: "Fork Member"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: user.id,
        organization_id: target_org.id,
        role: "user"
      })

    conn = get(conn, ~p"/#{organization.account.handle}/#{project.handle}")
    html = html_response(conn, 200)

    refute html =~ "id=\"project-fork-form\""
  end

  test "forks a repository into an admin organization", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    {:ok, target_org} =
      Accounts.create_organization(%{handle: "fork-destination", name: "Fork Destination"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: user.id,
        organization_id: target_org.id,
        role: "admin"
      })

    conn =
      conn
      |> with_csrf()
      |> post(~p"/#{organization.account.handle}/#{project.handle}/fork", %{
        "fork" => %{
          "organization_id" => to_string(target_org.id),
          "handle" => "demo-fork",
          "return_to" => ~p"/#{organization.account.handle}/#{project.handle}"
        }
      })

    assert redirected_to(conn) == ~p"/#{target_org.account.handle}/demo-fork"

    forked = Projects.get_project_by_handle(target_org.id, "demo-fork")
    assert forked.forked_from_id == project.id
    assert forked.organization_id == target_org.id
  end

  test "shows fork origin on forked repository", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, target_org} =
      Accounts.create_organization(%{handle: "forked-show", name: "Forked Show"})

    assert {:ok, _forked} =
             Projects.fork_project(project, target_org, %{handle: "demo-fork"})

    conn = get(conn, ~p"/#{target_org.account.handle}/demo-fork")
    html = html_response(conn, 200)

    assert html =~ "Forked from"
    assert html =~ "#{organization.account.handle}/#{project.handle}"
  end

  test "rejects forks to organizations without admin role", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

    {:ok, target_org} =
      Accounts.create_organization(%{handle: "fork-invalid", name: "Fork Invalid"})

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: user.id,
        organization_id: target_org.id,
        role: "user"
      })

    return_to = ~p"/#{organization.account.handle}/#{project.handle}"

    conn =
      conn
      |> with_csrf()
      |> post(~p"/#{organization.account.handle}/#{project.handle}/fork", %{
        "fork" => %{
          "organization_id" => target_org.id,
          "handle" => "demo-fork",
          "return_to" => return_to
        }
      })

    assert redirected_to(conn) == return_to

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Select an organization you administer to fork."

    assert is_nil(Projects.get_project_by_handle(target_org.id, "demo-fork"))
  end

  test "returns not found for private repositories", %{conn: conn, organization: organization} do
    {:ok, private_project} =
      Projects.create_project(%{
        handle: "private-demo",
        name: "Private Demo",
        organization_id: organization.id,
        visibility: "private"
      })

    conn = get(conn, ~p"/#{organization.account.handle}/#{private_project.handle}")
    assert response(conn, 404) =~ "Not found"
  end

  defp with_csrf(conn) do
    csrf_token = CSRFProtection.get_csrf_token()
    existing_session = Map.get(conn.private, :plug_session, %{})

    conn
    |> Plug.Test.init_test_session(existing_session)
    |> put_session("_csrf_token", CSRFProtection.dump_state())
    |> put_req_header("x-csrf-token", csrf_token)
  end
end
