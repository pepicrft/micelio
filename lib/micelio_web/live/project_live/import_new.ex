defmodule MicelioWeb.ProjectLive.ImportNew do
  use MicelioWeb, :live_view
  use Gettext, backend: MicelioWeb.Gettext

  alias Micelio.Accounts
  alias Micelio.Auth.GitHubHttpClient
  alias Micelio.Authorization
  alias Micelio.Projects
  alias Micelio.Repo
  alias MicelioWeb.PageMeta

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user |> Repo.preload(:account)

    organizations =
      Accounts.list_organizations_for_user_with_role(user, "admin")

    github_identity = Accounts.get_oauth_identity_for_user(user, :github)

    has_github_token =
      not is_nil(github_identity) and not is_nil(github_identity.access_token_encrypted)

    socket =
      socket
      |> assign(:page_title, gettext("Import project"))
      |> PageMeta.assign(
        description: gettext("Import a Git repository as a new project."),
        canonical_url: url(~p"/projects/import")
      )
      |> assign(:user_account, user.account)
      |> assign(:organizations, organizations)
      |> assign(:account_options, account_options(user.account, organizations))
      |> assign(:github_identity, github_identity)
      |> assign(:has_github_token, has_github_token)
      |> assign(:github_repos, [])
      |> assign(:loading_repos, false)
      |> assign(:repos_error, nil)
      |> assign(:selected_repo, nil)
      |> assign(:search_query, "")

    socket =
      if has_github_token and connected?(socket) do
        send(self(), :fetch_github_repos)
        assign(socket, :loading_repos, true)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_info(:fetch_github_repos, socket) do
    case fetch_github_repositories(socket.assigns.github_identity) do
      {:ok, repos} ->
        {:noreply,
         socket
         |> assign(:github_repos, repos)
         |> assign(:loading_repos, false)
         |> assign(:repos_error, nil)}

      {:error, reason} ->
        Logger.warning("Failed to fetch GitHub repos", reason: inspect(reason))

        {:noreply,
         socket
         |> assign(:github_repos, [])
         |> assign(:loading_repos, false)
         |> assign(
           :repos_error,
           gettext("Failed to load repositories. You may need to reconnect your GitHub account.")
         )}
    end
  end

  @impl true
  def handle_event("select_repo", %{"url" => url, "name" => name}, socket) do
    {:noreply, assign(socket, :selected_repo, %{url: url, name: name})}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected_repo, nil)}
  end

  @impl true
  def handle_event("search", params, socket) do
    query = params["value"] || ""
    {:noreply, assign(socket, :search_query, query)}
  end

  @impl true
  def handle_event("import", %{"account_id" => account_id}, socket) do
    url = socket.assigns.selected_repo && socket.assigns.selected_repo.url
    name = socket.assigns.selected_repo && socket.assigns.selected_repo.name

    cond do
      is_nil(url) or String.trim(url) == "" ->
        {:noreply, put_flash(socket, :error, gettext("Please select a repository."))}

      account_id == "personal" ->
        handle_personal_import(socket, url, name)

      true ->
        organization = find_organization(socket.assigns.organizations, account_id)

        if is_nil(organization) do
          {:noreply, put_flash(socket, :error, gettext("Please select an account."))}
        else
          create_project_and_import(socket, organization, url, name)
        end
    end
  end

  defp handle_personal_import(socket, url, name) do
    user = socket.assigns.current_user
    user_account = socket.assigns.user_account

    case find_personal_organization(socket.assigns.organizations, user_account.handle) do
      nil ->
        case Accounts.create_organization_for_user(user, %{
               handle: user_account.handle,
               name: user_account.handle
             }) do
          {:ok, organization} ->
            create_project_and_import(socket, organization, url, name)

          {:error, _changeset} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               gettext("Failed to create personal organization. Please try again.")
             )}
        end

      organization ->
        create_project_and_import(socket, organization, url, name)
    end
  end

  defp create_project_and_import(socket, organization, source_url, full_name) do
    user = socket.assigns.current_user

    if Authorization.authorize(:project_create, user, organization) == :ok do
      {handle, project_name} = parse_repo_name(full_name)

      project_attrs = %{
        "handle" => handle,
        "name" => project_name,
        "organization_id" => organization.id,
        "visibility" => "private",
        "url" => source_url
      }

      case Projects.create_project(project_attrs, user: user, organization: organization) do
        {:ok, project} ->
          import_attrs = %{source_url: source_url}

          case Projects.start_project_import(project, user, import_attrs) do
            {:ok, import} ->
              {:noreply,
               socket
               |> put_flash(:info, gettext("Project created. Import started."))
               |> push_navigate(
                 to: ~p"/#{organization.account.handle}/#{project.handle}/import/#{import.id}"
               )}

            {:error, reason} ->
              Logger.error("Failed to start import: #{inspect(reason)}")

              {:noreply,
               socket
               |> put_flash(
                 :error,
                 gettext(
                   "Project created but import failed to start. You can retry from settings."
                 )
               )
               |> push_navigate(
                 to: ~p"/#{organization.account.handle}/#{project.handle}/settings/import"
               )}
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          errors = format_changeset_errors(changeset)

          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("Failed to create project: %{errors}", errors: errors)
           )}
      end
    else
      {:noreply,
       put_flash(socket, :error, gettext("You do not have access to this organization."))}
    end
  end

  defp parse_repo_name(full_name) when is_binary(full_name) do
    case String.split(full_name, "/") do
      [_owner, repo] ->
        handle = slugify(repo)
        {handle, repo}

      _ ->
        handle = slugify(full_name)
        {handle, full_name}
    end
  end

  defp parse_repo_name(_), do: {"imported-project", "Imported Project"}

  defp slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/[\s_]+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "project"
      slug -> slug
    end
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp find_personal_organization(organizations, handle) do
    Enum.find(organizations, fn org ->
      org.account && org.account.handle == handle
    end)
  end

  defp fetch_github_repositories(identity) do
    token = identity.access_token_encrypted
    GitHubHttpClient.fetch_repositories(token, per_page: 100, sort: "updated")
  end

  defp account_options(user_account, organizations) do
    personal_option = {user_account.handle, "personal"}

    org_options =
      Enum.map(organizations, fn organization ->
        {organization.account.handle, organization.id}
      end)

    [personal_option | org_options]
  end

  defp find_organization(organizations, organization_id) do
    Enum.find(organizations, fn organization -> organization.id == organization_id end)
  end

  defp filter_repos(repos, ""), do: repos
  defp filter_repos(repos, nil), do: repos

  defp filter_repos(repos, query) do
    query = String.downcase(query)

    Enum.filter(repos, fn repo ->
      name = String.downcase(repo["full_name"] || "")
      description = String.downcase(repo["description"] || "")
      String.contains?(name, query) or String.contains?(description, query)
    end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, :filtered_repos, filter_repos(assigns.github_repos, assigns.search_query))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="import-container">
        <.header>
          {gettext("Import project")}
          <:subtitle>
            <p>{gettext("Import an existing Git repository as a new project.")}</p>
          </:subtitle>
        </.header>

        <%= if @has_github_token do %>
          <div class="import-content">
            <div class="import-github-panel" role="tabpanel">
              <%= if @loading_repos do %>
                <div class="import-loading">
                  <p>{gettext("Loading your repositories...")}</p>
                </div>
              <% else %>
                <%= if @repos_error do %>
                  <div class="import-error">
                    <p>{@repos_error}</p>
                    <.link
                      href={~p"/auth/github?#{[return_to: "/projects/import"]}"}
                      class="project-button"
                    >
                      {gettext("Reconnect GitHub")}
                    </.link>
                  </div>
                <% else %>
                  <%= if @selected_repo do %>
                    <div class="import-selected-repo">
                      <div class="import-selected-repo-info">
                        <strong>{@selected_repo.name}</strong>
                        <span class="import-selected-repo-url">{@selected_repo.url}</span>
                      </div>
                      <button
                        type="button"
                        class="import-clear-selection"
                        phx-click="clear_selection"
                        aria-label={gettext("Clear selection")}
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          width="16"
                          height="16"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <path d="M18 6 6 18" /><path d="m6 6 12 12" />
                        </svg>
                      </button>
                    </div>
                  <% else %>
                    <div class="import-search">
                      <input
                        type="text"
                        class="project-input import-search-input"
                        placeholder={gettext("Search repositories...")}
                        phx-keyup="search"
                        phx-debounce="150"
                        name="query"
                        value={@search_query}
                        autocomplete="off"
                      />
                    </div>
                    <div class="import-repo-list">
                      <%= if Enum.empty?(@filtered_repos) do %>
                        <p class="import-empty">
                          <%= if @search_query != "" do %>
                            {gettext("No repositories match your search.")}
                          <% else %>
                            {gettext("No repositories found.")}
                          <% end %>
                        </p>
                      <% else %>
                        <%= for repo <- @filtered_repos do %>
                          <button
                            type="button"
                            class="import-repo-item"
                            phx-click="select_repo"
                            phx-value-url={repo["clone_url"]}
                            phx-value-name={repo["full_name"]}
                          >
                            <div class="import-repo-name">
                              <span class="import-repo-fullname">{repo["full_name"]}</span>
                              <%= if repo["private"] do %>
                                <span class="import-repo-visibility import-repo-private">
                                  {gettext("Private")}
                                </span>
                              <% else %>
                                <span class="import-repo-visibility import-repo-public">
                                  {gettext("Public")}
                                </span>
                              <% end %>
                            </div>
                            <%= if repo["description"] do %>
                              <p class="import-repo-description">{repo["description"]}</p>
                            <% end %>
                          </button>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
              <div class="import-reconnect">
                <.link
                  href={~p"/auth/github?#{[return_to: "/projects/import"]}"}
                  class="import-reconnect-link"
                >
                  {gettext("Reconnect GitHub to update permissions")}
                </.link>
              </div>
            </div>

            <form class="import-form" phx-submit="import">
              <div class="import-form-group">
                <label for="account-select">{gettext("Account")}</label>
                <select
                  id="account-select"
                  name="account_id"
                  class="project-input"
                >
                  <%= for {label, value} <- @account_options do %>
                    <option value={value}>{label}</option>
                  <% end %>
                </select>
              </div>

              <div class="import-form-actions">
                <button
                  type="submit"
                  class="project-button"
                  disabled={is_nil(@selected_repo)}
                >
                  {gettext("Continue")}
                </button>
                <.link
                  navigate={~p"/projects"}
                  class="project-button project-button-secondary"
                >
                  {gettext("Cancel")}
                </.link>
              </div>
            </form>
          </div>
        <% else %>
          <div class="import-github-connect">
            <p>{gettext("Connect your GitHub account to import repositories directly.")}</p>
            <.link
              href={~p"/auth/github?#{[return_to: "/projects/import"]}"}
              class="project-button project-button-secondary"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M15 22v-4a4.8 4.8 0 0 0-1-3.5c3 0 6-2 6-5.5.08-1.25-.27-2.48-1-3.5.28-1.15.28-2.35 0-3.5 0 0-1 0-3 1.5-2.64-.5-5.36-.5-8 0C6 2 5 2 5 2c-.3 1.15-.3 2.35 0 3.5A5.403 5.403 0 0 0 4 9c0 3.5 3 5.5 6 5.5-.39.49-.68 1.05-.85 1.65-.17.6-.22 1.23-.15 1.85v4" />
                <path d="M9 18c-4.51 2-5-2-7-2" />
              </svg>
              {gettext("Connect GitHub")}
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
