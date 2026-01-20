defmodule MicelioWeb.SessionLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.{Authorization, Projects, Sessions}
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{
          "organization_handle" => org_handle,
          "project_handle" => project_handle,
          "id" => session_id
        },
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
          case Sessions.get_session_with_changes(session_id) do
            nil ->
              {:ok,
               socket
               |> put_flash(:error, "Session not found.")
               |> push_navigate(to: ~p"/projects/#{org_handle}/#{project_handle}/sessions")}

            session ->
              if session.project_id == project.id do
                change_stats = Sessions.get_session_change_stats(session)

                socket =
                  socket
                  |> assign(:page_title, "Session: #{session.goal}")
                  |> PageMeta.assign(
                    description: "Session details for #{project.name}.",
                    canonical_url:
                      url(
                        ~p"/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
                      ),
                    open_graph: %{
                      image_template: "agent_session",
                      image_stats: session_og_stats(change_stats)
                    }
                  )
                  |> assign(:project, project)
                  |> assign(:organization, organization)
                  |> assign(:session, session)
                  |> assign(:change_stats, change_stats)
                  |> assign_session_og_summary()

                {:ok, socket}
              else
                {:ok,
                 socket
                 |> put_flash(:error, "Session not found.")
                 |> push_navigate(to: ~p"/projects/#{org_handle}/#{project_handle}/sessions")}
              end
          end
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
  def handle_event("abandon", _params, socket) do
    session = socket.assigns.session

    if session.status == "active" do
      case Sessions.abandon_session(session) do
        {:ok, updated_session} ->
          {:noreply,
           socket
           |> assign(:session, updated_session)
           |> put_flash(:info, "Session abandoned successfully.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to abandon session.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only active sessions can be abandoned.")}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    session = socket.assigns.session
    organization = socket.assigns.organization
    project = socket.assigns.project

    if session.status in ["landed", "abandoned"] do
      case Sessions.delete_session(session) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Session deleted successfully.")
           |> push_navigate(
             to: ~p"/projects/#{organization.account.handle}/#{project.handle}/sessions"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete session.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only landed or abandoned sessions can be deleted.")}
    end
  end

  defp status_badge_class("active"), do: "status-badge-active"
  defp status_badge_class("landed"), do: "status-badge-landed"
  defp status_badge_class("abandoned"), do: "status-badge-abandoned"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %H:%M:%S UTC")
  end

  defp role_class("user"), do: "message-user"
  defp role_class("assistant"), do: "message-assistant"
  defp role_class(_), do: "message-system"

  defp format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 1)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 1)} GB"
    end
  end

  defp format_file_size(_), do: ""

  defp session_og_stats(%{total: total, added: added, modified: modified, deleted: deleted})
       when is_integer(total) and is_integer(added) and is_integer(modified) and is_integer(deleted) do
    %{
      files: total,
      added: added,
      modified: modified,
      deleted: deleted
    }
  end

  defp session_og_stats(_), do: %{}

  defp assign_session_og_summary(socket) do
    session = socket.assigns.session

    case Sessions.get_or_generate_og_summary(session, session.changes) do
      {:ok, summary} when is_binary(summary) and summary != "" ->
        PageMeta.assign(socket, description: summary)

      _ ->
        socket
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
      <div class="session-show-container">
        <header class="session-show-header">
          <div class="session-breadcrumb">
            <.link navigate={~p"/projects"}>Projects</.link>
            <span>/</span>
            <.link navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}"}>
              {@project.name}
            </.link>
            <span>/</span>
            <.link navigate={
              ~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions"
            }>
              Sessions
            </.link>
            <span>/</span>
            <span>{@session.goal}</span>
          </div>
          <div class="session-show-title">
            <h1>{@session.goal}</h1>
            <span class={"status-badge #{status_badge_class(@session.status)}"}>
              {String.capitalize(@session.status)}
            </span>
          </div>
          <div class="session-show-meta">
            <div>
              <strong>Started:</strong> {format_datetime(@session.started_at)}
            </div>
            <%= if @session.landed_at do %>
              <div>
                <strong>Completed:</strong> {format_datetime(@session.landed_at)}
              </div>
            <% end %>
            <%= if @session.user do %>
              <div>
                <strong>Author:</strong> {@session.user.email}
              </div>
            <% end %>
          </div>
        </header>

        <div class="session-show-actions">
          <%= if @session.status == "active" do %>
            <button
              type="button"
              class="session-action session-action-abandon"
              phx-click="abandon"
              phx-confirm="Abandon this session?"
            >
              Abandon Session
            </button>
          <% end %>
          <%= if @session.status in ["landed", "abandoned"] do %>
            <button
              type="button"
              class="session-action session-action-delete"
              phx-click="delete"
              phx-confirm="Delete this session permanently?"
            >
              Delete Session
            </button>
          <% end %>
        </div>

        <div class="session-content">
          <%= if not Enum.empty?(@session.conversation) do %>
            <section class="session-section">
              <h2>Conversation</h2>
              <div class="session-conversation">
                <%= for message <- @session.conversation do %>
                  <div class={"conversation-message #{role_class(message["role"])}"}>
                    <div class="message-role">
                      {String.capitalize(message["role"] || "unknown")}
                    </div>
                    <div class="message-content">
                      {message["content"]}
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>

          <%= if not Enum.empty?(@session.decisions) do %>
            <section class="session-section">
              <h2>Decisions</h2>
              <div class="session-decisions">
                <%= for decision <- @session.decisions do %>
                  <div class="decision-item">
                    <%= if decision["decision"] do %>
                      <div class="decision-text">
                        {decision["decision"]}
                      </div>
                    <% end %>
                    <%= if decision["reasoning"] do %>
                      <div class="decision-reasoning">
                        <strong>Reasoning:</strong> {decision["reasoning"]}
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>

          <%= if @session.metadata && map_size(@session.metadata) > 0 do %>
            <section class="session-section">
              <h2>Metadata</h2>
              <div class="session-metadata">
                <%= for {key, value} <- @session.metadata do %>
                  <div class="metadata-item">
                    <span class="metadata-key">{key}:</span>
                    <span class="metadata-value">{inspect(value)}</span>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>

          <section class="session-section">
            <h2>Changes</h2>
            <%= if @change_stats.total > 0 do %>
              <div class="session-changes-summary">
                <span class="change-stat change-stat-total">
                  {@change_stats.total} total
                </span>
                <%= if @change_stats.added > 0 do %>
                  <span class="change-stat change-stat-added">
                    +{@change_stats.added} added
                  </span>
                <% end %>
                <%= if @change_stats.modified > 0 do %>
                  <span class="change-stat change-stat-modified">
                    ~{@change_stats.modified} modified
                  </span>
                <% end %>
                <%= if @change_stats.deleted > 0 do %>
                  <span class="change-stat change-stat-deleted">
                    -{@change_stats.deleted} deleted
                  </span>
                <% end %>
              </div>
              <div class="session-changes-list">
                <%= for change <- @session.changes do %>
                  <div class={"change-item change-item-#{change.change_type}"}>
                    <div class="change-header">
                      <span class={"change-type-badge change-type-#{change.change_type}"}>
                        <%= case change.change_type do %>
                          <% "added" -> %>
                            +
                          <% "modified" -> %>
                            ~
                          <% "deleted" -> %>
                            -
                        <% end %>
                      </span>
                      <span class="change-path">{change.file_path}</span>
                      <%= if change.metadata["size"] do %>
                        <span class="change-size">
                          ({format_file_size(change.metadata["size"])})
                        </span>
                      <% end %>
                    </div>
                    <%= if change.content && change.change_type != "deleted" do %>
                      <details class="change-content">
                        <summary>View content</summary>
                        <pre><code>{change.content}</code></pre>
                      </details>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="info-message">
                No file changes in this session
              </p>
            <% end %>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
