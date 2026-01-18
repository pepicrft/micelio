defmodule Micelio.Projects do
  @moduledoc """
  The Projects context handles project management.
  Projects belong to organizations and have a unique handle within each organization.
  """

  import Ecto.Query

  alias Micelio.Accounts
  alias Micelio.Accounts.OrganizationMembership
  alias Micelio.Hif.Seed
  alias Micelio.Projects.{Project, ProjectStar}
  alias Micelio.Repo
  alias Micelio.Storage

  @micelio_workspace_email "micelio@micelio.dev"
  @micelio_workspace_org_handle "micelio"
  @micelio_workspace_org_name "Micelio"
  @micelio_workspace_project_handle "micelio"
  @micelio_workspace_project_name "Micelio"
  @micelio_workspace_project_description "The Micelio platform"
  @micelio_workspace_project_url "https://micelio.dev"
  @micelio_workspace_project_visibility "public"

  @doc """
  Gets a project by ID.
  """
  def get_project(id), do: Repo.get(Project, id)

  @doc """
  Gets a project by ID with organization preloaded.
  """
  def get_project_with_organization(id) do
    Project
    |> Repo.get(id)
    |> Repo.preload(organization: :account)
  end

  @doc """
  Preloads fork origin details for a project.
  """
  def preload_fork_origin(%Project{} = project) do
    Repo.preload(project, forked_from: [organization: :account])
  end

  @doc """
  Gets a project by organization ID and handle (case-insensitive).
  """
  def get_project_by_handle(organization_id, handle) do
    Project
    |> where([p], p.organization_id == ^organization_id)
    |> where([p], fragment("lower(?)", p.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Lists all projects for an organization.
  """
  def list_projects_for_organization(organization_id) do
    Project
    |> where([p], p.organization_id == ^organization_id)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Lists public projects for an organization.
  """
  def list_public_projects_for_organization(organization_id) do
    list_public_projects_for_organizations([organization_id])
  end

  @doc """
  Lists public projects for a set of organization IDs.
  """
  def list_public_projects_for_organizations([]), do: []

  def list_public_projects_for_organizations(organization_ids) do
    Project
    |> where([p], p.organization_id in ^organization_ids and p.visibility == "public")
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([_p, o, a], organization: {o, account: a})
    |> order_by([_p, _o, a], asc: a.handle)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Lists all projects.
  """
  def list_projects do
    Repo.all(Project)
  end

  @doc """
  Ensures the Micelio workspace project exists with default metadata.
  """
  def ensure_micelio_workspace do
    Repo.transaction(fn ->
      with {:ok, user} <- Accounts.get_or_create_user_by_email(@micelio_workspace_email),
           {:ok, organization} <- ensure_micelio_organization(),
           {:ok, _membership} <- ensure_micelio_membership(user, organization),
           {:ok, project} <- ensure_micelio_project(organization) do
        %{user: user, organization: organization, project: project}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Seeds the Micelio workspace storage from a local path.
  """
  def seed_micelio_workspace(root_path, opts \\ []) when is_binary(root_path) do
    with {:ok, %{project: project} = data} <- ensure_micelio_workspace() do
      case Seed.seed_project_from_path(project.id, root_path, opts) do
        {:ok, seed_result} -> {:ok, Map.merge(data, seed_result)}
        {:error, :already_seeded} -> {:ok, Map.put(data, :already_seeded, true)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Seeds the Micelio workspace if a source path is configured or provided.
  """
  def seed_micelio_workspace_if_configured(opts \\ []) do
    seed_opts = Keyword.get(opts, :seed_opts, [])
    project = Keyword.get(opts, :project)

    case workspace_path_from_opts(opts) do
      nil ->
        {:ok, :skipped}

      path ->
        seed_micelio_workspace_with_project(project, path, seed_opts)
    end
  end

  @doc """
  Searches projects by name and description using full-text search.
  """
  def search_projects(raw_query, opts \\ []) do
    query = normalize_search_query(raw_query)

    if query == "" do
      []
    else
      user = Keyword.get(opts, :user)
      limit = Keyword.get(opts, :limit, 50)

      Project
      |> join(:inner, [p], f in "projects_fts", on: field(f, :project_id) == p.id)
      |> where([_p, _f], fragment("projects_fts MATCH ?", ^query))
      |> search_visibility_filter(user)
      |> join(:left, [p, _f], o in assoc(p, :organization))
      |> join(:left, [p, _f, o], a in assoc(o, :account))
      |> preload([_p, _f, o, a], organization: {o, account: a})
      |> order_by([_p, _f], fragment("bm25(projects_fts)"))
      |> limit(^limit)
      |> Repo.all()
    end
  end

  @doc """
  Lists all projects for the organizations a user belongs to.
  Projects are ordered by organization handle and project name.
  """
  def list_projects_for_user(user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    list_projects_for_organizations(organization_ids)
  end

  @doc """
  Lists all projects for a set of organization IDs.
  """
  def list_projects_for_organizations([]), do: []

  def list_projects_for_organizations(organization_ids) do
    Project
    |> where([p], p.organization_id in ^organization_ids)
    |> join(:left, [p], o in assoc(p, :organization))
    |> join(:left, [p, o], a in assoc(o, :account))
    |> preload([p, o, a], organization: {o, account: a})
    |> order_by([_p, _o, a], asc: a.handle)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Creates a new project.
  """
  def create_project(attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Forks a project into a new organization, copying storage and tracking origin.
  """
  def fork_project(%Project{} = source, %Accounts.Organization{} = organization, attrs \\ %{}) do
    attrs = normalize_fork_attrs(source, organization, attrs)

    Repo.transaction(fn ->
      case create_fork_project(source, attrs) do
        {:ok, project} ->
          case copy_project_storage(source.id, project.id) do
            :ok -> project
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates repository settings (name, description, visibility).
  """
  def update_project_settings(%Project{} = project, attrs) do
    project
    |> Project.settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for repository settings changes.
  """
  def change_project_settings(%Project{} = project, attrs \\ %{}) do
    Project.settings_changeset(project, attrs)
  end

  @doc """
  Returns the count of stars for a project.
  """
  def count_project_stars(%Project{} = project) do
    ProjectStar
    |> where([ps], ps.project_id == ^project.id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns true if the user has starred the project.
  """
  def project_starred?(%Accounts.User{} = user, %Project{} = project) do
    not is_nil(get_project_star(user, project))
  end

  def project_starred?(_, _), do: false

  @doc """
  Stars a project for a user.
  """
  def star_project(%Accounts.User{} = user, %Project{} = project) do
    case get_project_star(user, project) do
      %ProjectStar{} = star ->
        {:ok, star}

      nil ->
        %ProjectStar{}
        |> ProjectStar.changeset(%{user_id: user.id, project_id: project.id})
        |> Repo.insert()
    end
  end

  @doc """
  Removes a star from a project for a user.
  """
  def unstar_project(%Accounts.User{} = user, %Project{} = project) do
    case get_project_star(user, project) do
      nil -> {:ok, :not_found}
      %ProjectStar{} = star -> Repo.delete(star)
    end
  end

  defp get_project_star(%Accounts.User{} = user, %Project{} = project) do
    Repo.get_by(ProjectStar, user_id: user.id, project_id: project.id)
  end

  @doc """
  Lists starred projects for a user with organization and account preloaded.
  """
  def list_starred_projects_for_user(%Accounts.User{} = user) do
    Project
    |> join(:inner, [p], ps in ProjectStar, on: ps.project_id == p.id)
    |> where([_p, ps], ps.user_id == ^user.id)
    |> join(:left, [p, _ps], o in assoc(p, :organization))
    |> join(:left, [p, _ps, o], a in assoc(o, :account))
    |> preload([_p, _ps, o, a], organization: {o, account: a})
    |> order_by([_p, ps], desc: ps.inserted_at)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Checks if a handle is available for a given organization.
  """
  def handle_available?(organization_id, handle) do
    is_nil(get_project_by_handle(organization_id, handle))
  end

  @doc """
  Gets a project by organization handle and project handle for a user.
  """
  def get_project_for_user_by_handle(user, organization_handle, project_handle) do
    with {:ok, organization} <- Accounts.get_organization_by_handle(organization_handle),
         %Project{} = project <- get_project_by_handle(organization.id, project_handle) do
      cond do
        project.visibility == "public" ->
          {:ok, project, organization}

        user_in_organization?(user, organization.id) ->
          {:ok, project, organization}

        true ->
          {:error, :unauthorized}
      end
    else
      nil -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp user_in_organization?(%Accounts.User{} = user, organization_id),
    do: Accounts.user_in_organization?(user, organization_id)

  defp user_in_organization?(_, _), do: false

  defp ensure_micelio_organization do
    case Accounts.get_organization_by_handle(@micelio_workspace_org_handle) do
      {:ok, organization} ->
        {:ok, organization}

      {:error, :not_found} ->
        Accounts.create_organization(
          %{
            handle: @micelio_workspace_org_handle,
            name: @micelio_workspace_org_name
          },
          allow_reserved: true
        )
    end
  end

  defp ensure_micelio_membership(%Accounts.User{} = user, %Accounts.Organization{} = organization) do
    case Repo.get_by(OrganizationMembership,
           user_id: user.id,
           organization_id: organization.id
         ) do
      nil ->
        Accounts.create_organization_membership(%{
          user_id: user.id,
          organization_id: organization.id,
          role: "admin"
        })

      %OrganizationMembership{} = membership ->
        {:ok, membership}
    end
  end

  defp ensure_micelio_project(%Accounts.Organization{} = organization) do
    attrs = %{
      handle: @micelio_workspace_project_handle,
      name: @micelio_workspace_project_name,
      description: @micelio_workspace_project_description,
      url: @micelio_workspace_project_url,
      visibility: @micelio_workspace_project_visibility,
      organization_id: organization.id
    }

    case get_project_by_handle(organization.id, @micelio_workspace_project_handle) do
      nil ->
        create_project(attrs)

      %Project{} = project ->
        update_attrs =
          Enum.reduce([:description, :url], %{}, fn key, acc ->
            value = Map.get(project, key)
            desired = Map.get(attrs, key)

            if value in [nil, ""], do: Map.put(acc, key, desired), else: acc
          end)

        update_attrs =
          if project.visibility == @micelio_workspace_project_visibility do
            update_attrs
          else
            Map.put(update_attrs, :visibility, @micelio_workspace_project_visibility)
          end

        if update_attrs == %{} do
          {:ok, project}
        else
          update_project(project, update_attrs)
        end
    end
  end

  defp seed_micelio_workspace_with_project(nil, path, seed_opts) do
    seed_micelio_workspace(path, seed_opts)
  end

  defp seed_micelio_workspace_with_project(%Project{} = project, path, seed_opts) do
    case Seed.seed_project_from_path(project.id, path, seed_opts) do
      {:ok, seed_result} -> {:ok, Map.merge(%{project: project}, seed_result)}
      {:error, :already_seeded} -> {:ok, %{project: project, already_seeded: true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp workspace_path_from_opts(opts) do
    case Keyword.get(opts, :path, Application.get_env(:micelio, :micelio_workspace_path)) do
      path when is_binary(path) ->
        trimmed = String.trim(path)
        if trimmed != "", do: trimmed

      _ ->
        nil
    end
  end

  defp normalize_search_query(query) when is_binary(query) do
    tokens =
      query
      |> String.downcase()
      |> then(&Regex.scan(~r/[[:alnum:]]+/u, &1))
      |> List.flatten()

    case tokens do
      [] -> ""
      _ -> tokens |> Enum.map_join(" AND ", &"#{&1}*")
    end
  end

  defp normalize_search_query(_), do: ""

  defp normalize_fork_attrs(%Project{} = source, %Accounts.Organization{} = organization, attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put_new("handle", source.handle)
      |> Map.put_new("name", source.name)
      |> Map.put_new("description", source.description)
      |> Map.put_new("url", source.url)
      |> Map.put_new("visibility", source.visibility)
      |> Map.put("organization_id", organization.id)

    attrs
  end

  defp create_fork_project(%Project{} = source, attrs) do
    %Project{}
    |> Project.changeset(attrs)
    |> Ecto.Changeset.put_change(:forked_from_id, source.id)
    |> Repo.insert()
  end

  defp copy_project_storage(source_id, target_id) do
    source_prefix = project_storage_prefix(source_id)
    target_prefix = project_storage_prefix(target_id)

    with {:ok, keys} <- Storage.list(source_prefix) do
      Enum.reduce_while(keys, :ok, fn key, :ok ->
        target_key = String.replace_prefix(key, source_prefix, target_prefix)

        with {:ok, content} <- Storage.get(key),
             {:ok, _} <- Storage.put(target_key, content) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp project_storage_prefix(project_id), do: "projects/#{project_id}"

  defp search_visibility_filter(query, %Accounts.User{} = user) do
    organization_ids =
      user
      |> Accounts.list_organizations_for_user()
      |> Enum.map(& &1.id)

    if organization_ids == [] do
      where(query, [p, _f], p.visibility == "public")
    else
      where(
        query,
        [p, _f],
        p.visibility == "public" or p.organization_id in ^organization_ids
      )
    end
  end

  defp search_visibility_filter(query, _user) do
    where(query, [p, _f], p.visibility == "public")
  end
end
