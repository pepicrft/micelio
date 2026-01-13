defmodule MicelioWeb.SessionLive.Index do
  use MicelioWeb, :live_view

  alias Micelio.{Authorization, Projects, Sessions}

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
          socket =
            socket
            |> assign(:page_title, "Sessions - #{project.name}")
            |> assign(:project, project)
            |> assign(:organization, organization)
            |> assign(:status_filter, "all")
            |> assign(:sort_order, :newest)
            |> load_sessions()

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
  def handle_event("filter", %{"status" => status}, socket) do
    socket =
      socket
      |> assign(:status_filter, status)
      |> load_sessions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    socket =
      socket
      |> assign(:sort_order, normalize_sort(sort))
      |> load_sessions()

    {:noreply, socket}
  end

  defp load_sessions(socket) do
    status_filter = socket.assigns.status_filter
    sort_order = socket.assigns.sort_order
    project = socket.assigns.project

    opts =
      []
      |> maybe_put(:status, status_filter)
      |> Keyword.put(:sort, sort_order)

    sessions = Sessions.list_sessions_for_project(project, opts)

    assign(socket, :sessions, sessions)
  end

  defp maybe_put(opts, _key, "all"), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp normalize_sort("oldest"), do: :oldest
  defp normalize_sort("status"), do: :status
  defp normalize_sort(_), do: :newest

  defp status_badge_class("active"), do: "status-badge-active"
  defp status_badge_class("landed"), do: "status-badge-landed"
  defp status_badge_class("abandoned"), do: "status-badge-abandoned"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="sessions-container">
        <header class="sessions-header">
          <div>
            <h1>Sessions</h1>
            <div class="sessions-breadcrumb">
              <.link navigate={~p"/projects"}>Projects</.link>
              <span>/</span>
              <.link navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}"}>
                {@project.name}
              </.link>
              <span>/</span>
              <span>Sessions</span>
            </div>
          </div>
        </header>

        <div class="sessions-controls">
          <div class="sessions-filters">
            <button
              type="button"
              class={"filter-button #{if @status_filter == "all", do: "active", else: ""}"}
              phx-click="filter"
              phx-value-status="all"
            >
              All
            </button>
            <button
              type="button"
              class={"filter-button #{if @status_filter == "active", do: "active", else: ""}"}
              phx-click="filter"
              phx-value-status="active"
            >
              Active
            </button>
            <button
              type="button"
              class={"filter-button #{if @status_filter == "landed", do: "active", else: ""}"}
              phx-click="filter"
              phx-value-status="landed"
            >
              Landed
            </button>
            <button
              type="button"
              class={"filter-button #{if @status_filter == "abandoned", do: "active", else: ""}"}
              phx-click="filter"
              phx-value-status="abandoned"
            >
              Abandoned
            </button>
          </div>

          <form class="sessions-sort" phx-change="sort">
            <label for="sort-order">Sort</label>
            <select id="sort-order" name="sort">
              <option value="newest" selected={@sort_order == :newest}>Newest first</option>
              <option value="oldest" selected={@sort_order == :oldest}>Oldest first</option>
              <option value="status" selected={@sort_order == :status}>By status</option>
            </select>
          </form>
        </div>

        <%= if Enum.empty?(@sessions) do %>
          <div class="sessions-empty">
            <p>No sessions found.</p>
          </div>
        <% else %>
          <div class="sessions-list">
            <%= for session <- @sessions do %>
              <.link
                navigate={
                  ~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions/#{session.id}"
                }
                class="session-card"
              >
                <div class="session-card-header">
                  <h3 class="session-goal">{session.goal}</h3>
                  <span class={"status-badge #{status_badge_class(session.status)}"}>
                    {String.capitalize(session.status)}
                  </span>
                </div>
                <div class="session-card-meta">
                  <span>Started: {format_datetime(session.started_at)}</span>
                  <%= if session.landed_at do %>
                    <span>•</span>
                    <span>Completed: {format_datetime(session.landed_at)}</span>
                  <% end %>
                </div>
                <div class="session-card-stats">
                  <span>{length(session.conversation)} messages</span>
                  <span>•</span>
                  <span>{length(session.decisions)} decisions</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
