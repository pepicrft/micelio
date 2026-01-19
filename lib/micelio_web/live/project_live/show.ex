defmodule MicelioWeb.ProjectLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Notifications
  alias Micelio.Projects
  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{"organization_handle" => org_handle, "project_handle" => project_handle},
        _session,
        socket
      ) do
    case Projects.get_project_for_user_by_handle(
           socket.assigns.current_user,
           org_handle,
           project_handle
         ) do
      {:ok, project, organization} ->
        if Authorization.authorize(:project_read, socket.assigns.current_user, project) == :ok do
          recent_sessions =
            Sessions.list_sessions_for_project(project)
            |> Enum.take(5)

          session_count = Sessions.count_sessions_for_project(project)

          socket =
            socket
            |> assign(:page_title, project.name)
            |> PageMeta.assign(
              description: project.description || "Project overview.",
              canonical_url: url(~p"/projects/#{organization.account.handle}/#{project.handle}")
            )
            |> assign(:project, project)
            |> assign(:organization, organization)
            |> assign(:recent_sessions, recent_sessions)
            |> assign(:session_count, session_count)
            |> assign_star_data()

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this project.")
           |> push_navigate(to: ~p"/projects")}
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
      {:ok, _} = Projects.delete_project(project, user: user)

      {:noreply,
       socket
       |> put_flash(:info, "Project deleted successfully.")
       |> push_navigate(to: ~p"/projects")}
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this project.")}
    end
  end

  @impl true
  def handle_event("toggle_star", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    if socket.assigns.starred? do
      _ = Projects.unstar_project(user, project)
    else
      case Projects.star_project(user, project) do
        {:ok, _star} ->
          _ = Notifications.dispatch_project_starred(project, user)
          :ok

        {:error, _changeset} ->
          :error
      end
    end

    {:noreply, assign_star_data(socket)}
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
        <.header>
          {@project.name}
          <:subtitle>
            <div class="project-show-handle">
              {@organization.account.handle}/{@project.handle}
            </div>
            <%= if @project.description do %>
              <p class="project-show-description">{@project.description}</p>
            <% end %>
            <%= if @project.url do %>
              <p class="project-show-url">
                <a href={@project.url} target="_blank" rel="noopener noreferrer">
                  {@project.url}
                </a>
              </p>
            <% end %>
          </:subtitle>
          <:actions>
            <div class="project-show-stars">
              <button
                type="button"
                class="project-show-action project-show-action-star"
                id="project-star-toggle"
                phx-click="toggle_star"
              >
                <%= if @starred? do %>
                  Unstar
                <% else %>
                  Star
                <% end %>
              </button>
              <span class="project-show-stars-count" id="project-stars-count">
                Stars: {@stars_count}
              </span>
            </div>
            <%= if Authorization.authorize(:project_update, @current_user, @project) == :ok do %>
              <.link
                navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}/edit"}
                class="project-show-action project-show-action-edit"
                id="project-edit"
              >
                Edit
              </.link>
              <button
                type="button"
                class="project-show-action project-show-action-delete"
                id="project-delete"
                phx-click="delete"
                phx-confirm="Delete this project?"
              >
                Delete
              </button>
            <% end %>
          </:actions>
        </.header>

        <div class="project-show-navigation">
          <.link
            navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions"}
            class="project-show-nav-link"
          >
            Sessions ({@session_count})
          </.link>
        </div>

        <%= if not Enum.empty?(@recent_sessions) do %>
          <div class="project-recent-sessions">
            <h2>Recent Sessions</h2>
            <div class="sessions-list-compact">
              <%= for session <- @recent_sessions do %>
                <.link
                  navigate={
                    ~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions/#{session.id}"
                  }
                  class="session-card-compact"
                >
                  <div class="session-card-content">
                    <div class="session-goal-compact">{session.goal}</div>
                    <span class={"status-badge status-badge-#{session.status}"}>
                      {String.capitalize(session.status)}
                    </span>
                  </div>
                </.link>
              <% end %>
            </div>
            <.link
              navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions"}
              class="project-show-action"
            >
              View all sessions
            </.link>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp assign_star_data(socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    socket
    |> assign(:starred?, Projects.project_starred?(user, project))
    |> assign(:stars_count, Projects.count_project_stars(project))
  end
end
