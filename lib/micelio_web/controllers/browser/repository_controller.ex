defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  alias Micelio.Hif.Binary
  alias Micelio.Hif.Repository, as: MicRepository
  alias MicelioWeb.PageMeta

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

  defp render_tree(conn, account_handle, repository_handle, dir_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
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
    |> assign(:head, head)
    |> assign(:dir_path, dir_path)
    |> assign(:entries, MicRepository.list_entries(tree, dir_path))
    |> render(:show)
  end

  defp render_blob(conn, account_handle, repository_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         {:ok, head} <- MicRepository.get_head(repository.id) do
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
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:file_content, format_file_content(content))
          |> render(:blob)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
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
end
