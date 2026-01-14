defmodule Micelio.GRPC.Content.V1.ContentService.Server do
  use GRPC.Server, service: Micelio.GRPC.Content.V1.ContentService.Service

  alias GRPC.RPCError
  alias GRPC.Status
  alias Micelio.Accounts
  alias Micelio.GRPC.Content.V1

  alias Micelio.GRPC.Content.V1.{
    GetBlobRequest,
    GetBlobResponse,
    GetHeadTreeRequest,
    GetPathRequest,
    GetPathResponse,
    GetTreeRequest,
    GetTreeResponse,
    TreeEntry
  }

  alias Micelio.Mic.Binary
  alias Micelio.Mic.Tree, as: MicTree
  alias Micelio.OAuth.AccessTokens
  alias Micelio.Projects
  alias Micelio.Storage

  @zero_hash <<0::size(256)>>

  def get_head_tree(%GetHeadTreeRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.project_handle, "project_handle"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.account_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, request.project_handle),
         {:ok, tree_hash, tree} <- load_head_tree(project.id) do
      %GetTreeResponse{tree: %V1.Tree{entries: tree_entries(tree)}, tree_hash: tree_hash}
    else
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this account.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_tree(%GetTreeRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.project_handle, "project_handle"),
         :ok <- require_hash(request.tree_hash, "tree_hash"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.account_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, request.project_handle),
         {:ok, tree} <- load_tree(project.id, request.tree_hash) do
      %GetTreeResponse{tree: %V1.Tree{entries: tree_entries(tree)}, tree_hash: request.tree_hash}
    else
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this account.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_blob(%GetBlobRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.project_handle, "project_handle"),
         :ok <- require_hash(request.blob_hash, "blob_hash"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.account_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, request.project_handle),
         {:ok, content} <- load_blob(project.id, request.blob_hash) do
      %GetBlobResponse{content: content}
    else
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this account.")}
      {:error, status} -> {:error, status}
    end
  end

  def get_path(%GetPathRequest{} = request, stream) do
    with :ok <- require_field(request.account_handle, "account_handle"),
         :ok <- require_field(request.project_handle, "project_handle"),
         :ok <- require_field(request.path, "path"),
         {:ok, user} <- fetch_user(request.user_id, stream),
         {:ok, organization} <- Accounts.get_organization_by_handle(request.account_handle),
         true <- Accounts.user_in_organization?(user, organization.id),
         project when not is_nil(project) <-
           Projects.get_project_by_handle(organization.id, request.project_handle),
         {:ok, _tree_hash, tree} <- load_head_tree(project.id),
         {:ok, blob_hash} <- fetch_path_hash(tree, request.path),
         {:ok, content} <- load_blob(project.id, blob_hash) do
      %GetPathResponse{content: content, blob_hash: blob_hash}
    else
      nil -> {:error, not_found_status("Project not found.")}
      false -> {:error, forbidden_status("You do not have access to this account.")}
      {:error, status} -> {:error, status}
    end
  end

  defp fetch_path_hash(tree, path) do
    case Map.fetch(tree, path) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, not_found_status("Path not found.")}
    end
  end

  defp load_head_tree(project_id) do
    case Storage.get(head_key(project_id)) do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content),
             {:ok, tree} <- load_tree(project_id, head.tree_hash) do
          {:ok, head.tree_hash, tree}
        else
          {:error, _} -> {:error, internal_status("Failed to decode head.")}
        end

      {:error, :not_found} ->
        {:ok, Binary.zero_hash(), MicTree.empty()}

      {:error, _reason} ->
        {:error, internal_status("Failed to load head.")}
    end
  end

  defp load_tree(_project_id, tree_hash) when tree_hash == @zero_hash, do: {:ok, MicTree.empty()}

  defp load_tree(project_id, tree_hash) do
    case Storage.get(tree_key(project_id, tree_hash)) do
      {:ok, content} ->
        case MicTree.decode(content) do
          {:ok, tree} -> {:ok, tree}
          {:error, _} -> {:error, internal_status("Failed to decode tree.")}
        end

      {:error, :not_found} ->
        {:error, not_found_status("Tree not found.")}

      {:error, _reason} ->
        {:error, internal_status("Failed to load tree.")}
    end
  end

  defp load_blob(project_id, blob_hash) do
    case Storage.get(blob_key(project_id, blob_hash)) do
      {:ok, content} -> {:ok, content}
      {:error, :not_found} -> {:error, not_found_status("Blob not found.")}
      {:error, _reason} -> {:error, internal_status("Failed to load blob.")}
    end
  end

  defp tree_entries(tree) do
    tree
    |> Map.to_list()
    |> Enum.sort_by(fn {path, _hash} -> path end)
    |> Enum.map(fn {path, hash} -> %TreeEntry{path: path, hash: hash} end)
  end

  defp head_key(project_id), do: "projects/#{project_id}/head"

  defp tree_key(project_id, tree_hash) do
    hash_hex = Base.encode16(tree_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "projects/#{project_id}/trees/#{prefix}/#{hash_hex}.bin"
  end

  defp blob_key(project_id, blob_hash) do
    hash_hex = Base.encode16(blob_hash, case: :lower)
    prefix = String.slice(hash_hex, 0, 2)
    "projects/#{project_id}/blobs/#{prefix}/#{hash_hex}.bin"
  end

  defp fetch_user(user_id, stream) do
    case empty_to_nil(user_id) do
      nil -> fetch_user_from_token(stream)
      value -> fetch_user_by_id(value)
    end
  end

  defp fetch_user_by_id(user_id) do
    case Accounts.get_user(user_id) do
      nil -> {:error, unauthenticated_status("User not found.")}
      user -> {:ok, user}
    end
  end

  defp fetch_user_from_token(stream) do
    with {:ok, token} <- fetch_bearer_token(stream),
         %Boruta.Oauth.Token{} = access_token <- AccessTokens.get_by(value: token),
         user when not is_nil(user) <- Accounts.get_user(access_token.sub) do
      {:ok, user}
    else
      _ -> {:error, unauthenticated_status("User is required.")}
    end
  end

  defp fetch_bearer_token(stream) do
    case Map.get(stream.http_request_headers, "authorization") do
      "Bearer " <> token -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  defp require_field(value, field_name) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, invalid_status("#{field_name} is required.")}
    else
      :ok
    end
  end

  defp require_field(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp empty_to_nil(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: trimmed
  end

  defp empty_to_nil(_value), do: nil

  defp require_hash(value, field_name) when is_binary(value) do
    if byte_size(value) == 32 do
      :ok
    else
      {:error, invalid_status("#{field_name} must be a 32-byte hash.")}
    end
  end

  defp require_hash(_value, field_name),
    do: {:error, invalid_status("#{field_name} is required.")}

  defp invalid_status(message), do: rpc_error(Status.invalid_argument(), message)
  defp not_found_status(message), do: rpc_error(Status.not_found(), message)
  defp forbidden_status(message), do: rpc_error(Status.permission_denied(), message)
  defp unauthenticated_status(message), do: rpc_error(Status.unauthenticated(), message)
  defp internal_status(message), do: rpc_error(Status.internal(), message)

  defp rpc_error(status, message) do
    RPCError.exception(status: status, message: message)
  end
end
