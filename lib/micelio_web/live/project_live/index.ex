defmodule MicelioWeb.ProjectLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Projects
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects_for_user(socket.assigns.current_user)

    admin_organizations =
      Accounts.list_organizations_for_user_with_role(socket.assigns.current_user, "admin")

    socket =
      socket
      |> assign(:page_title, "Projects")
      |> PageMeta.assign(
        description: "Manage your projects.",
        canonical_url: url(~p"/projects")
      )
      |> assign(:projects_count, length(projects))
      |> assign(:can_create_project, admin_organizations != [])
      |> stream(:projects, projects)

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_user

    case Projects.get_project_with_organization(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Project not found.")}

      project ->
        if Authorization.authorize(:project_delete, user, project) == :ok do
          {:ok, _} = Projects.delete_project(project, user: user)
          projects_count = max(socket.assigns.projects_count - 1, 0)

          {:noreply,
           socket
           |> stream_delete(:projects, project)
           |> assign(:projects_count, projects_count)
           |> put_flash(:info, "Project deleted successfully.")}
        else
          {:noreply, put_flash(socket, :error, "You do not have access to this project.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="projects-container">
        <.header>
          Projects
          <:actions>
            <.link
              navigate={~p"/organizations/new"}
              class="project-button project-button-secondary"
              id="new-organization-link"
            >
              New organization
            </.link>
            <%= if @can_create_project do %>
              <.link navigate={~p"/projects/new"} class="project-button" id="new-project-link">
                New project
              </.link>
            <% end %>
          </:actions>
        </.header>

        <%= if @projects_count == 0 do %>
          <div class="projects-empty">
            <h2>No projects yet</h2>
            <p>Projects help you organize your code and collaborate with others.</p>
            <%= if @can_create_project do %>
              <.link navigate={~p"/projects/new"} class="project-button" id="projects-empty-create">
                Create your first project
              </.link>
            <% end %>
          </div>
        <% else %>
          <div id="projects" phx-update="stream" class="projects-list">
            <div :for={{id, project} <- @streams.projects} id={id} class="project-card">
              <div class="project-card-name">{project.name}</div>
              <div class="project-card-handle">
                @{project.organization.account.handle}/{project.handle}
              </div>
              <%= if project.description do %>
                <div class="project-card-description">{project.description}</div>
              <% end %>
              <%= if project.url do %>
                <div class="project-card-url">
                  <a href={project.url} target="_blank" rel="noopener noreferrer">
                    {project.url}
                  </a>
                </div>
              <% end %>
              <div class="project-card-actions">
                <.link
                  navigate={~p"/projects/#{project.organization.account.handle}/#{project.handle}"}
                  class="project-card-action"
                  id={"project-view-#{project.id}"}
                >
                  View
                </.link>
                <%= if Authorization.authorize(:project_update, @current_user, project) == :ok do %>
                  <.link
                    navigate={
                      ~p"/projects/#{project.organization.account.handle}/#{project.handle}/edit"
                    }
                    class="project-card-action"
                    id={"project-edit-#{project.id}"}
                  >
                    Edit
                  </.link>
                  <button
                    type="button"
                    class="project-card-action project-card-action-danger"
                    id={"project-delete-#{project.id}"}
                    phx-click="delete"
                    phx-value-id={project.id}
                    phx-confirm="Delete this project?"
                  >
                    Delete
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
