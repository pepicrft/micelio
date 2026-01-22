defmodule MicelioWeb.SessionLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.{Authorization, Projects, Sessions}
  alias Micelio.Sessions.EventSchema
  alias MicelioWeb.PageMeta

  @event_snapshot_limit 50
  @max_session_events 200

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
                  |> assign(:event_types, EventSchema.event_types())
                  |> load_event_snapshot()
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

  defp prompt_request_title(%{title: title, id: id}) do
    case title do
      value when is_binary(value) and String.trim(value) != "" -> value
      _ -> "Prompt request #{id}"
    end
  end

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

  defp load_event_snapshot(socket) do
    session = socket.assigns.session

    case Sessions.list_session_events(session.session_id, limit: @event_snapshot_limit) do
      {:ok, events} ->
        last_cursor =
          case List.last(events) do
            %{storage_key: storage_key} -> storage_key
            _ -> nil
          end

        socket
        |> assign(:event_snapshot, events)
        |> assign(:event_after_cursor, last_cursor)

      {:error, _reason} ->
        socket
        |> assign(:event_snapshot, [])
        |> assign(:event_after_cursor, nil)
    end
  end

  defp event_type(%{"type" => type}) when is_binary(type), do: type
  defp event_type(_event), do: "unknown"

  defp event_payload(%{"payload" => payload}) when is_map(payload), do: payload
  defp event_payload(_event), do: %{}

  defp event_output_text(event) do
    payload = event_payload(event)

    if event_type(event) == "output" and is_binary(payload["text"]) do
      payload["text"]
    end
  end

  defp event_output_stream(event) do
    payload = event_payload(event)

    if event_type(event) == "output" and is_binary(payload["stream"]) do
      payload["stream"]
    end
  end

  defp output_open?(output) when is_binary(output) do
    String.length(output) <= 240
  end

  defp output_open?(_output), do: false

  defp event_summary(event) do
    payload = event_payload(event)

    case event_type(event) do
      "status" ->
        parts =
          []
          |> maybe_push(payload["state"])
          |> maybe_push(payload["message"])
          |> maybe_push(format_percent(payload["percent"]))

        Enum.join(parts, " - ")

      "progress" ->
        cond do
          is_number(payload["percent"]) ->
            join_summary([format_percent(payload["percent"]), payload["message"]])

          is_number(payload["current"]) and is_number(payload["total"]) ->
            unit = payload["unit"] || ""

            "#{payload["current"]}/#{payload["total"]} #{unit}"
            |> String.trim()
            |> then(&join_summary([&1, payload["message"]]))

          is_binary(payload["message"]) ->
            payload["message"]

          true ->
            ""
        end

      "output" ->
        payload["text"]
        |> truncate_text(140)

      "error" ->
        if is_binary(payload["message"]), do: payload["message"], else: ""

      "artifact" ->
        cond do
          is_binary(payload["name"]) -> payload["name"]
          is_binary(payload["uri"]) -> payload["uri"]
          true -> ""
        end

      _ ->
        ""
    end
  end

  defp format_percent(nil), do: nil
  defp format_percent(percent) when is_number(percent), do: "#{percent}%"
  defp format_percent(_), do: nil

  defp join_summary(parts) when is_list(parts) do
    parts
    |> Enum.filter(fn part -> is_binary(part) and part != "" end)
    |> Enum.join(" - ")
  end

  defp event_progress_percent(event) do
    payload = event_payload(event)

    percent =
      cond do
        is_number(payload["percent"]) ->
          payload["percent"]

        is_number(payload["current"]) and is_number(payload["total"]) and payload["total"] > 0 ->
          payload["current"] / payload["total"] * 100

        true ->
          nil
      end

    if is_number(percent) do
      percent
      |> max(0)
      |> min(100)
    end
  end

  defp maybe_push(list, value) when is_binary(value) and value != "", do: list ++ [value]
  defp maybe_push(list, value) when is_number(value), do: list ++ ["#{value}"]
  defp maybe_push(list, _value), do: list

  defp truncate_text(nil, _max), do: ""

  defp truncate_text(text, max) when is_binary(text) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end

  defp format_event_timestamp(nil), do: nil

  defp format_event_timestamp(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} ->
        Calendar.strftime(datetime, "%b %d, %Y %H:%M:%S UTC")

      _ ->
        timestamp
    end
  end

  defp event_timestamp_attr(nil), do: nil

  defp event_timestamp_attr(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _offset} -> DateTime.to_iso8601(datetime)
      _ -> nil
    end
  end

  defp format_event_source(%{"label" => label}) when is_binary(label) and label != "", do: label

  defp format_event_source(%{"kind" => kind}) when is_binary(kind) and kind != "" do
    String.capitalize(kind)
  end

  defp format_event_source(_source), do: "System"

  defp artifact_uri(%{"uri" => uri}) when is_binary(uri) and uri != "", do: uri
  defp artifact_uri(_payload), do: nil

  defp artifact_label(payload) do
    cond do
      is_binary(payload["name"]) and payload["name"] != "" -> payload["name"]
      is_binary(payload["uri"]) and payload["uri"] != "" -> payload["uri"]
      true -> "Artifact"
    end
  end

  defp artifact_detail(payload) do
    parts =
      []
      |> maybe_push(payload["kind"])
      |> maybe_push(format_file_size(payload["size_bytes"]))

    join_summary(parts)
  end

  defp artifact_image?(payload) do
    kind = payload["kind"]
    content_type = payload["content_type"]
    uri = payload["uri"]

    cond do
      kind == "image" ->
        true

      is_binary(content_type) and String.starts_with?(content_type, "image/") ->
        true

      is_binary(uri) ->
        String.downcase(uri)
        |> String.ends_with?([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"])

      true ->
        false
    end
  end

  defp event_payload_json(event) do
    Jason.encode!(event, pretty: true)
  end

  defp event_type_icon("status"), do: "S"
  defp event_type_icon("progress"), do: "P"
  defp event_type_icon("output"), do: "O"
  defp event_type_icon("error"), do: "E"
  defp event_type_icon("artifact"), do: "A"
  defp event_type_icon(_type), do: "?"

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
            <%= if @session.prompt_request do %>
              <div>
                <strong>Prompt request:</strong>
                <.link
                  navigate={
                    ~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests/#{@session.prompt_request.id}"
                  }
                  class="session-prompt-request-link"
                  id="session-prompt-request-link"
                >
                  {prompt_request_title(@session.prompt_request)}
                </.link>
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

          <section
            id="session-event-viewer"
            class="session-section session-event-viewer"
            phx-hook="SessionEventViewer"
            data-events-url={
              ~p"/api/sessions/#{@session.session_id}/events/stream"
            }
            data-after={@event_after_cursor}
            data-max-events={@max_session_events}
          >
            <div class="session-event-heading">
              <h2>Session events</h2>
              <span class="session-event-status" data-role="event-status" data-state="connecting">
                Connecting...
              </span>
            </div>
            <div class="session-event-filters" role="group" aria-label="Filter session events">
              <%= for type <- @event_types do %>
                <label class="session-event-filter">
                  <input type="checkbox" name="event-types" value={type} checked />
                  <span class={"session-event-pill session-event-pill-#{type}"}>
                    <span class={"session-event-icon session-event-icon-#{type}"} aria-hidden="true">
                      {event_type_icon(type)}
                    </span>
                    {String.capitalize(type)}
                  </span>
                </label>
              <% end %>
            </div>
            <div class="session-event-stream">
              <p
                class="session-event-empty"
                data-role="event-empty"
                hidden={Enum.any?(@event_snapshot)}
              >
                No events yet.
              </p>
              <div
                class="session-event-list"
                id="session-event-list"
                data-role="event-list"
                role="log"
                aria-live="polite"
                aria-relevant="additions"
                phx-update="ignore"
              >
                <%= for %{event: event} <- @event_snapshot do %>
                  <article
                    class={"session-event-card session-event-#{event_type(event)}"}
                    data-type={event_type(event)}
                  >
                    <div class="session-event-card-header">
                      <span class={"session-event-type session-event-type-#{event_type(event)}"}>
                        <span
                          class={"session-event-icon session-event-icon-#{event_type(event)}"}
                          aria-hidden="true"
                        >
                          {event_type_icon(event_type(event))}
                        </span>
                        {String.capitalize(event_type(event))}
                      </span>
                      <%= if timestamp = format_event_timestamp(event["timestamp"]) do %>
                        <time
                          class="session-event-time"
                          datetime={event_timestamp_attr(event["timestamp"])}
                        >
                          {timestamp}
                        </time>
                      <% end %>
                      <span class="session-event-source">
                        {format_event_source(event["source"])}
                      </span>
                    </div>
                    <%= if summary = event_summary(event) do %>
                      <%= if summary != "" do %>
                        <div class="session-event-summary">{summary}</div>
                      <% end %>
                    <% end %>
                    <%= if percent = event_progress_percent(event) do %>
                      <div
                        class="session-event-progress"
                        role="progressbar"
                        aria-valuemin="0"
                        aria-valuemax="100"
                        aria-valuenow={percent}
                      >
                        <div class="session-event-progress-track">
                          <div
                            class="session-event-progress-bar"
                            style={"width: #{percent}%"}
                          >
                          </div>
                        </div>
                        <span class="session-event-progress-label">{format_percent(percent)}</span>
                      </div>
                    <% end %>
                    <%= if event_type(event) == "artifact" do %>
                      <% payload = event_payload(event) %>
                      <%= if uri = artifact_uri(payload) do %>
                        <div class="session-event-artifact">
                          <%= if artifact_image?(payload) do %>
                            <a
                              class="session-event-artifact-link"
                              href={uri}
                              target="_blank"
                              rel="noopener"
                            >
                              <img
                                class="session-event-artifact-image"
                                src={uri}
                                alt={artifact_label(payload)}
                                loading="lazy"
                              />
                            </a>
                          <% else %>
                            <a
                              class="session-event-artifact-link"
                              href={uri}
                              target="_blank"
                              rel="noopener"
                            >
                              {artifact_label(payload)}
                            </a>
                          <% end %>
                          <%= if detail = artifact_detail(payload) do %>
                            <%= if detail != "" do %>
                              <div class="session-event-artifact-meta">{detail}</div>
                            <% end %>
                          <% end %>
                        </div>
                      <% end %>
                    <% end %>
                    <%= if output = event_output_text(event) do %>
                      <details class="session-event-output-block" open={output_open?(output)}>
                        <summary>
                          Output
                          <%= if stream = event_output_stream(event) do %>
                            <span class="session-event-output-stream">
                              {String.upcase(stream)}
                            </span>
                          <% end %>
                        </summary>
                        <pre class="session-event-output">{output}</pre>
                      </details>
                    <% end %>
                    <details class="session-event-details" data-role="event-details">
                      <summary>Details</summary>
                      <pre class="session-event-payload"><code>{event_payload_json(event)}</code></pre>
                    </details>
                  </article>
                <% end %>
              </div>
            </div>
          </section>

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
