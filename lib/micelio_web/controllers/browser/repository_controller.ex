defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Hif.Binary
  alias Micelio.Hif.Repository, as: MicRepository
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias MicelioWeb.Markdown
  alias MicelioWeb.PageMeta
  alias MicelioWeb.CodeHighlighter

  def show(conn, %{"account" => account_handle, "repository" => repository_handle}) do
    render_tree(conn, account_handle, repository_handle, "")
  end

  def tree(conn, %{"account" => account_handle, "repository" => repository_handle, "path" => path}) do
    render_tree(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def tree(conn, %{"account" => account_handle, "repository" => repository_handle}) do
    render_tree(conn, account_handle, repository_handle, "")
  end

  def blob(conn, %{"account" => account_handle, "repository" => repository_handle, "path" => path}) do
    render_blob(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def blame(conn, %{"account" => account_handle, "repository" => repository_handle, "path" => path}) do
    render_blame(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def toggle_star(conn, %{"account" => account_handle, "repository" => repository_handle} = params) do
    return_to = get_in(params, ["star", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      if Projects.project_starred?(user, repository) do
        _ = Projects.unstar_project(user, repository)
      else
        _ = Projects.star_project(user, repository)
      end

      redirect(conn,
        to: safe_return_path(return_to, account_handle, repository_handle)
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def fork(conn, %{"account" => account_handle, "repository" => repository_handle} = params) do
    return_to = get_in(params, ["fork", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, target_org} <- resolve_fork_target(user, params),
         {:ok, forked} <- Projects.fork_project(repository, target_org, fork_attrs(params)) do
      redirect(conn, to: ~p"/#{target_org.account.handle}/#{forked.handle}")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, format_fork_errors(changeset))
        |> redirect(to: safe_return_path(return_to, account_handle, repository_handle))

      {:error, :invalid_target} ->
        conn
        |> put_flash(:error, "Select an organization you administer to fork.")
        |> redirect(to: safe_return_path(return_to, account_handle, repository_handle))

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp render_tree(conn, account_handle, repository_handle, dir_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicRepository.get_head(repository.id) do
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicRepository.get_tree(repository.id, head.tree_hash) do
        dir_path = String.trim(dir_path || "", "/")

        cond do
          dir_path == "" ->
            render_tree_page(
              conn,
              account_handle,
              repository_handle,
              account,
              repository,
              head,
              tree,
              dir_path
            )

          MicRepository.blob_hash_for_path(tree, dir_path) ->
            redirect(conn, to: ~p"/#{account_handle}/#{repository_handle}/blob/#{dir_path}")

          MicRepository.directory_exists?(tree, dir_path) ->
            render_tree_page(
              conn,
              account_handle,
              repository_handle,
              account,
              repository,
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
         repository_handle,
         account,
         repository,
         head,
         tree,
         dir_path
       ) do
    repository = Projects.preload_fork_origin(repository)
    entries = MicRepository.list_entries(tree, dir_path)

    readme =
      if dir_path == "" do
        readme_for_root(repository.id, tree, entries)
      end

    title_parts =
      if dir_path == "" do
        ["#{account_handle}/#{repository_handle}"]
      else
        [dir_path, "#{account_handle}/#{repository_handle}"]
      end

    conn
    |> PageMeta.put(
      title_parts: title_parts,
      description: repository.description,
      canonical_url:
        if dir_path == "" do
          url(~p"/#{account_handle}/#{repository_handle}")
        else
          url(~p"/#{account_handle}/#{repository_handle}/tree/#{dir_path}")
        end
    )
    |> assign(:account, account)
    |> assign(:repository, repository)
    |> assign(:forked_from, repository.forked_from)
    |> assign(:head, head)
    |> assign(:dir_path, dir_path)
    |> assign(:entries, entries)
    |> assign(:readme, readme)
    |> assign_star_data(repository)
    |> assign_fork_data(repository)
    |> render(:show)
  end

  defp render_blob(conn, account_handle, repository_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicRepository.get_head(repository.id) do
      repository = Projects.preload_fork_origin(repository)
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicRepository.get_tree(repository.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicRepository.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicRepository.get_blob(repository.id, blob_hash) do
          title_parts = [file_path, "#{account_handle}/#{repository_handle}"]

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: repository.description,
            canonical_url: url(~p"/#{account_handle}/#{repository_handle}/blob/#{file_path}")
          )
          |> assign(:account, account)
          |> assign(:repository, repository)
          |> assign(:forked_from, repository.forked_from)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:file_content, format_blob_content(file_path, content))
          |> assign_star_data(repository)
          |> assign_fork_data(repository)
          |> render(:blob)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp render_blame(conn, account_handle, repository_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicRepository.get_head(repository.id) do
      repository = Projects.preload_fork_origin(repository)
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicRepository.get_tree(repository.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicRepository.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicRepository.get_blob(repository.id, blob_hash) do
          title_parts = ["Blame", file_path, "#{account_handle}/#{repository_handle}"]
          blame_content = format_file_content(content)

          blame_lines =
            case blame_content do
              {:text, text} ->
                repository.id
                |> Sessions.list_landed_changes_for_file(file_path)
                |> then(&Blame.build_lines(text, &1))
                |> Enum.map(&format_blame_line/1)

              _ ->
                []
            end

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: repository.description,
            canonical_url: url(~p"/#{account_handle}/#{repository_handle}/blame/#{file_path}")
          )
          |> assign(:account, account)
          |> assign(:repository, repository)
          |> assign(:forked_from, repository.forked_from)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:blame_content, blame_content)
          |> assign(:blame_lines, blame_lines)
          |> assign_star_data(repository)
          |> assign_fork_data(repository)
          |> render(:blame)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp assign_star_data(conn, repository) do
    return_to = current_path(conn)

    conn
    |> assign(:star_form, Phoenix.Component.to_form(%{"return_to" => return_to}, as: :star))
    |> assign(:starred?, Projects.project_starred?(conn.assigns.current_user, repository))
    |> assign(:stars_count, Projects.count_project_stars(repository))
  end

  defp assign_fork_data(conn, repository) do
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
          "handle" => repository.handle,
          "name" => repository.name
        },
        as: :fork
      )

    conn
    |> assign(:fork_form, form)
    |> assign(:fork_organizations, fork_organizations)
    |> assign(:fork_organization_options, fork_organization_options(fork_organizations))
  end

  defp safe_return_path(return_to, account_handle, repository_handle) do
    if is_binary(return_to) and String.starts_with?(return_to, "/") do
      return_to
    else
      ~p"/#{account_handle}/#{repository_handle}"
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
    case Integer.parse(org_id) do
      {parsed, ""} -> parsed
      _ -> nil
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
        with blob_hash when is_binary(blob_hash) <- MicRepository.blob_hash_for_path(tree, entry.path),
             {:ok, content} <- MicRepository.get_blob(project_id, blob_hash) do
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
    |> then(&(&1 in @readme_markdown_extensions))
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

  defp format_blame_date(nil), do: "unknown"
  defp format_blame_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
end
