defmodule MicelioWeb.ProjectLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Projects

  @impl true
  def mount(%{"organization_handle" => org_handle, "project_handle" => project_handle}, _session, socket) do
    case Projects.get_project_for_user_by_handle(
           socket.assigns.current_user,
           org_handle,
           project_handle
         ) do
      {:ok, project, organization} ->
        if Authorization.authorize(:project_read, socket.assigns.current_user, project) != :ok do
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this project.")
           |> push_navigate(to: ~p"/projects")}
        else
          socket =
            socket
            |> assign(:page_title, project.name)
            |> assign(:project, project)
            |> assign(:organization, organization)

          {:ok, socket}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    if Authorization.authorize(:project_delete, user, project) == :ok do
      {:ok, _} = Projects.delete_project(project)

      {:noreply,
       socket
       |> put_flash(:info, "Project deleted successfully.")
       |> push_navigate(to: ~p"/projects")}
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this project.")}
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
      <div class="project-show-container">
        <header class="project-show-header">
          <h1>{@project.name}</h1>
          <div class="project-show-handle">
            {@organization.account.handle}/{@project.handle}
          </div>
          <%= if @project.description do %>
            <p class="project-show-description">{@project.description}</p>
          <% end %>
        </header>

        <div class="project-show-actions">
          <%= if Authorization.authorize(:project_update, @current_user, @project) == :ok do %>
            <.link
              navigate={
                ~p"/projects/#{@organization.account.handle}/#{@project.handle}/edit"
              }
              class="project-show-action project-show-action-edit"
              id="project-edit"
            >
              Edit project
            </.link>
            <button
              type="button"
              class="project-show-action project-show-action-delete"
              id="project-delete"
              phx-click="delete"
              phx-confirm="Delete this project?"
            >
              Delete project
            </button>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
