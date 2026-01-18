defmodule MicelioWeb.Browser.ProjectController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Hif.Binary
  alias Micelio.Hif.Project, as: MicProject
  alias Micelio.Notifications
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias MicelioWeb.CodeHighlighter
  alias MicelioWeb.Markdown
  alias MicelioWeb.PageMeta
  alias MicelioWeb.SchemaOrg

  def show(conn, %{"account" => account_handle, "project" => project_handle}) do
    render_tree(conn, account_handle, project_handle, "")
  end

  def tree(conn, %{"account" => account_handle, "project" => project_handle, "path" => path}) do
    render_tree(conn, account_handle, project_handle, Enum.join(path, "/"))
  end

  def tree(conn, %{"account" => account_handle, "project" => project_handle}) do
    render_tree(conn, account_handle, project_handle, "")
  end

  def blob(conn, %{"account" => account_handle, "project" => project_handle, "path" => path}) do
    render_blob(conn, account_handle, project_handle, Enum.join(path, "/"))
  end

  def blame(conn, %{"account" => account_handle, "project" => project_handle, "path" => path}) do
    render_blame(conn, account_handle, project_handle, Enum.join(path, "/"))
  end

  def toggle_star(conn, %{"account" => account_handle, "project" => project_handle} = params) do
    return_to = get_in(params, ["star", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_project,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:project_read, user, project) do
      if Projects.project_starred?(user, project) do
        _ = Projects.unstar_project(user, project)
      else
        case Projects.star_project(user, project) do
          {:ok, _star} -> _ = Notifications.dispatch_project_starred(project, user)
          {:error, _changeset} -> :error
        end
      end

      redirect(conn,
        to: safe_return_path(return_to, account_handle, project_handle)
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def fork(conn, %{"account" => account_handle, "project" => project_handle} = params) do
    return_to = get_in(params, ["fork", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_project,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:project_read, user, project),
         {:ok, target_org} <- resolve_fork_target(user, params),
         {:ok, forked} <- Projects.fork_project(project, target_org, fork_attrs(params)) do
      redirect(conn, to: ~p"/#{target_org.account.handle}/#{forked.handle}")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, format_fork_errors(changeset))
        |> redirect(to: safe_return_path(return_to, account_handle, project_handle))

      {:error, :invalid_target} ->
        conn
        |> put_flash(:error, "Select an organization you administer to fork.")
        |> redirect(to: safe_return_path(return_to, account_handle, project_handle))

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp render_tree(conn, account_handle, project_handle, dir_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_project,
         :ok <- Authorization.authorize(:project_read, conn.assigns.current_user, project),
         {:ok, head} <- MicProject.get_head(project.id) do
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(project.id, head.tree_hash) do
        dir_path = String.trim(dir_path || "", "/")

        cond do
          dir_path == "" ->
            render_tree_page(
              conn,
              account_handle,
              project_handle,
              account,
              project,
              head,
              tree,
              dir_path
            )

          MicProject.blob_hash_for_path(tree, dir_path) ->
            redirect(conn,
              to: ~p"/#{account_handle}/#{project_handle}/blob/#{path_segments(dir_path)}"
            )

          MicProject.directory_exists?(tree, dir_path) ->
            render_tree_page(
              conn,
              account_handle,
              project_handle,
              account,
              project,
              head,
              tree,
              dir_path
            )

          true ->
            send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp render_tree_page(
         conn,
         account_handle,
         project_handle,
         account,
         project,
         head,
         tree,
         dir_path
       ) do
    project = Projects.preload_fork_origin(project)
    entries = MicProject.list_entries(tree, dir_path)

    readme =
      if dir_path == "" do
        readme_for_root(project.id, tree, entries)
      end

    title_parts =
      if dir_path == "" do
        ["#{account_handle}/#{project_handle}"]
      else
        [dir_path, "#{account_handle}/#{project_handle}"]
      end

    conn
    |> PageMeta.put(
      title_parts: title_parts,
      description: project.description,
      canonical_url:
        if dir_path == "" do
          url(~p"/#{account_handle}/#{project_handle}")
        else
          url(~p"/#{account_handle}/#{project_handle}/tree/#{path_segments(dir_path)}")
        end
    )
    |> assign(:account, account)
    |> assign(:project, project)
    |> assign(:forked_from, project.forked_from)
    |> assign(:head, head)
    |> assign(:dir_path, dir_path)
    |> assign(:entries, entries)
    |> assign(:readme, readme)
    |> assign_star_data(project)
    |> assign_fork_data(project)
    |> assign_badge_data(account, project)
    |> maybe_assign_schema_json_ld(dir_path, account, project)
    |> render(:show)
  end

  defp render_blob(conn, account_handle, project_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_project,
         :ok <- Authorization.authorize(:project_read, conn.assigns.current_user, project),
         {:ok, head} <- MicProject.get_head(project.id) do
      project = Projects.preload_fork_origin(project)
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(project.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicProject.get_blob(project.id, blob_hash) do
          title_parts = [file_path, "#{account_handle}/#{project_handle}"]

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: project.description,
            canonical_url:
              url(~p"/#{account_handle}/#{project_handle}/blob/#{path_segments(file_path)}")
          )
          |> assign(:account, account)
          |> assign(:project, project)
          |> assign(:forked_from, project.forked_from)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:file_content, format_blob_content(file_path, content))
          |> assign_star_data(project)
          |> assign_fork_data(project)
          |> render(:blob)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp render_blame(conn, account_handle, project_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         project when not is_nil(project) <- conn.assigns.selected_project,
         :ok <- Authorization.authorize(:project_read, conn.assigns.current_user, project),
         {:ok, head} <- MicProject.get_head(project.id) do
      project = Projects.preload_fork_origin(project)
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(project.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicProject.get_blob(project.id, blob_hash) do
          title_parts = ["Blame", file_path, "#{account_handle}/#{project_handle}"]
          blame_content = format_file_content(content)

          blame_lines =
            case blame_content do
              {:text, text} ->
                project.id
                |> Sessions.list_landed_changes_for_file(file_path)
                |> then(&Blame.build_lines(text, &1))
                |> Enum.map(&format_blame_line/1)

              _ ->
                []
            end

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: project.description,
            canonical_url:
              url(~p"/#{account_handle}/#{project_handle}/blame/#{path_segments(file_path)}")
          )
          |> assign(:account, account)
          |> assign(:project, project)
          |> assign(:forked_from, project.forked_from)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:blame_content, blame_content)
          |> assign(:blame_lines, blame_lines)
          |> assign_star_data(project)
          |> assign_fork_data(project)
          |> render(:blame)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp maybe_assign_schema_json_ld(conn, dir_path, account, project) do
    if dir_path == "" do
      assign(conn, :schema_json_ld, project_schema_json_ld(account, project))
    else
      conn
    end
  end

  defp project_schema_json_ld(account, project) do
    project_url = url(~p"/#{account.handle}/#{project.handle}")
    author_url = url(~p"/#{account.handle}")

    account
    |> SchemaOrg.software_source_code(project,
      url: project_url,
      code_repository: project_url,
      author_url: author_url
    )
    |> SchemaOrg.encode()
  end

  defp assign_star_data(conn, project) do
    return_to = current_path(conn)

    conn
    |> assign(:star_form, Phoenix.Component.to_form(%{"return_to" => return_to}, as: :star))
    |> assign(:starred?, Projects.project_starred?(conn.assigns.current_user, project))
    |> assign(:stars_count, Projects.count_project_stars(project))
  end

  defp assign_fork_data(conn, project) do
    user = conn.assigns.current_user

    fork_organizations =
      if user do
        Accounts.list_organizations_for_user_with_role(user, "admin")
      else
        []
      end

    default_org_id =
      case fork_organizations do
        [%{id: id} | _] -> id
        _ -> nil
      end

    form =
      Phoenix.Component.to_form(
        %{
          "return_to" => current_path(conn),
          "organization_id" => default_org_id,
          "handle" => project.handle,
          "name" => project.name
        },
        as: :fork
      )

    conn
    |> assign(:fork_form, form)
    |> assign(:fork_organizations, fork_organizations)
    |> assign(:fork_organization_options, fork_organization_options(fork_organizations))
  end

  defp assign_badge_data(conn, account, project) do
    if project.visibility == "public" do
      badge_url = url(~p"/#{account.handle}/#{project.handle}/badge.svg")
      project_url = url(~p"/#{account.handle}/#{project.handle}")
      badge_label = "#{account.handle}/#{project.handle}"

      badge_markdown = "[![#{badge_label}](#{badge_url})](#{project_url})"

      badge_html =
        "<a href=\"#{project_url}\"><img src=\"#{badge_url}\" alt=\"#{badge_label} badge\" /></a>"

      conn
      |> assign(:badge_visible?, true)
      |> assign(:badge_url, badge_url)
      |> assign(:badge_markdown, badge_markdown)
      |> assign(:badge_html, badge_html)
    else
      assign(conn, :badge_visible?, false)
    end
  end

  defp safe_return_path(return_to, account_handle, project_handle) do
    if is_binary(return_to) and String.starts_with?(return_to, "/") do
      return_to
    else
      ~p"/#{account_handle}/#{project_handle}"
    end
  end

  defp resolve_fork_target(%Accounts.User{} = user, params) do
    org_id = normalize_fork_org_id(get_in(params, ["fork", "organization_id"]))

    organizations =
      Accounts.list_organizations_for_user_with_role(user, "admin")

    case Enum.find(organizations, fn organization -> organization.id == org_id end) do
      %Accounts.Organization{} = organization -> {:ok, organization}
      _ -> {:error, :invalid_target}
    end
  end

  defp fork_attrs(params) do
    params
    |> Map.get("fork", %{})
    |> Map.take(["handle", "name"])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case normalize_fork_value(value) do
        nil -> acc
        normalized -> Map.put(acc, key, normalized)
      end
    end)
  end

  defp normalize_fork_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_fork_value(_value), do: nil

  defp normalize_fork_org_id(org_id) when is_integer(org_id), do: org_id

  defp normalize_fork_org_id(org_id) when is_binary(org_id) do
    case Ecto.UUID.cast(org_id) do
      {:ok, uuid} ->
        uuid

      :error ->
        case Integer.parse(org_id) do
          {parsed, ""} -> parsed
          _ -> nil
        end
    end
  end

  defp normalize_fork_org_id(_org_id), do: nil

  defp fork_organization_options(organizations) do
    Enum.map(organizations, fn organization ->
      {"#{organization.account.handle} (#{organization.name})", organization.id}
    end)
  end

  defp format_fork_errors(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    case errors do
      %{handle: [msg | _]} -> "Fork failed: handle #{msg}."
      %{name: [msg | _]} -> "Fork failed: name #{msg}."
      %{organization_id: [msg | _]} -> "Fork failed: organization #{msg}."
      _ -> "Fork failed. Please check the details and try again."
    end
  end

  defp format_file_content(content) when is_binary(content) do
    limit = 200_000
    content = if byte_size(content) > limit, do: binary_part(content, 0, limit), else: content

    if String.valid?(content) do
      {:text, content}
    else
      {:binary, byte_size(content)}
    end
  end

  defp format_blob_content(file_path, content) when is_binary(content) do
    limit = 200_000
    content = if byte_size(content) > limit, do: binary_part(content, 0, limit), else: content

    if String.valid?(content) do
      case CodeHighlighter.highlight(file_path, content) do
        {:ok, highlighted} -> {:highlighted, highlighted}
        :no_lexer -> {:text, content}
      end
    else
      {:binary, byte_size(content)}
    end
  end

  @readme_candidates ["readme.md", "readme.markdown", "readme.mdown", "readme.txt", "readme"]
  @readme_markdown_extensions [".md", ".markdown", ".mdown"]

  defp readme_for_root(project_id, tree, entries) do
    case find_readme_entry(entries) do
      nil ->
        nil

      entry ->
        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, entry.path),
             {:ok, content} <- MicProject.get_blob(project_id, blob_hash) do
          %{path: entry.path, content: format_readme_content(entry.path, content)}
        else
          _ -> nil
        end
    end
  end

  defp find_readme_entry(entries) do
    Enum.find_value(@readme_candidates, fn candidate ->
      Enum.find(entries, fn entry ->
        entry.type == :blob and String.downcase(entry.name) == candidate
      end)
    end)
  end

  defp format_readme_content(path, content) when is_binary(path) and is_binary(content) do
    case format_file_content(content) do
      {:text, text} ->
        if markdown_readme?(path) do
          case Markdown.render(text) do
            {:ok, html} -> {:html, html}
            {:error, html} when is_binary(html) and html != "" -> {:html, html}
            {:error, _} -> {:text, text}
          end
        else
          {:text, text}
        end

      other ->
        other
    end
  end

  defp markdown_readme?(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> Kernel.in(@readme_markdown_extensions)
  end

  defp format_blame_line(%{attribution: attribution} = line) do
    session = if attribution, do: Map.get(attribution, :session)
    account = if session, do: session.user && session.user.account

    %{
      line_number: line.line_number,
      text: line.text,
      author_handle: if(account, do: account.handle),
      session_id: if(session, do: session.session_id),
      landed_at: format_blame_date(session && session.landed_at)
    }
  end

  defp path_segments(path) when is_binary(path) do
    String.split(path, "/", trim: true)
  end

  defp format_blame_date(nil), do: "unknown"
  defp format_blame_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
end
