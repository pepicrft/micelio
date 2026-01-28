defmodule MicelioWeb.ProjectLive.ImportProgress do
  use MicelioWeb, :live_view
  use Gettext, backend: MicelioWeb.Gettext

  alias Micelio.Authorization
  alias Micelio.Projects
  alias Micelio.Projects.ProjectImport
  alias MicelioWeb.PageMeta

  @refresh_ms 2_000

  @impl true
  def mount(
        %{"account" => account_handle, "project" => project_handle, "import_id" => import_id},
        _session,
        socket
      ) do
    case Projects.get_project_for_user_by_handle(
           socket.assigns.current_user,
           account_handle,
           project_handle
         ) do
      {:ok, project, organization} ->
        if Authorization.authorize(:project_update, socket.assigns.current_user, project) == :ok do
          import = Projects.get_project_import(import_id)

          if import && import.project_id == project.id do
            if connected?(socket) do
              Phoenix.PubSub.subscribe(Micelio.PubSub, import_topic(import.id))
            end

            socket =
              socket
              |> assign(:page_title, gettext("Import progress"))
              |> PageMeta.assign(
                description: gettext("View the progress of your project import."),
                canonical_url:
                  url(~p"/#{organization.account.handle}/#{project.handle}/import/#{import.id}")
              )
              |> assign(:project, project)
              |> assign(:organization, organization)
              |> assign(:import, import)
              |> assign(:stages, ProjectImport.stages())

            {:ok, schedule_refresh(socket)}
          else
            {:ok,
             socket
             |> put_flash(:error, gettext("Import not found."))
             |> push_navigate(to: ~p"/#{account_handle}/#{project_handle}")}
          end
        else
          {:ok,
           socket
           |> put_flash(:error, gettext("You do not have access to this project."))
           |> push_navigate(to: ~p"/#{account_handle}/#{project_handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_info(:refresh_import, socket) do
    import = Projects.get_project_import(socket.assigns.import.id)

    socket =
      socket
      |> assign(:import, import)
      |> schedule_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:import_updated, import}, socket) do
    {:noreply, assign(socket, :import, import)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="import-progress">
        <div class="import-progress-breadcrumb">
          <.link navigate={~p"/#{@organization.account.handle}/#{@project.handle}"}>
            {@organization.account.handle}/{@project.handle}
          </.link>
          <span>/</span>
          <span>{gettext("Import")}</span>
        </div>

        <.header>
          {gettext("Import progress")}
          <:subtitle>
            <p>{gettext("Importing from %{url}", url: @import.source_url)}</p>
          </:subtitle>
        </.header>

        <div class="import-progress-status-card">
          <div class="import-progress-status-header">
            <div class="import-progress-status-badge import-progress-status-{@import.status}">
              {status_label(@import.status)}
            </div>
            <div class="import-progress-stage">
              {gettext("Stage: %{stage}", stage: stage_label(@import.stage))}
            </div>
          </div>

          <%= if @import.error_message do %>
            <div class="import-progress-error">
              <strong>{gettext("Error:")}</strong> {@import.error_message}
            </div>
          <% end %>
        </div>

        <div class="import-progress-stages">
          <h2>{gettext("Stages")}</h2>
          <ul class="import-progress-stage-list">
            <%= for stage <- @stages do %>
              <li class={"import-progress-stage-item import-progress-stage-#{stage_state(stage, @import)}"}>
                <div class="import-progress-stage-icon">
                  {stage_icon(stage_state(stage, @import))}
                </div>
                <div class="import-progress-stage-info">
                  <span class="import-progress-stage-label">{stage_label(stage)}</span>
                  <span class="import-progress-stage-state">
                    {stage_state_label(stage_state(stage, @import))}
                  </span>
                </div>
              </li>
            <% end %>
          </ul>
        </div>

        <div class="import-progress-actions">
          <%= if import_completed?(@import) do %>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@project.handle}"}
              class="project-button"
            >
              {gettext("View project")}
            </.link>
          <% else %>
            <%= if import_failed?(@import) do %>
              <.link
                navigate={~p"/#{@organization.account.handle}/#{@project.handle}/settings/import"}
                class="project-button"
              >
                {gettext("Retry import")}
              </.link>
            <% end %>
          <% end %>

          <.link
            navigate={~p"/#{@organization.account.handle}/#{@project.handle}/settings/import"}
            class="project-button project-button-secondary"
          >
            {gettext("Import settings")}
          </.link>
        </div>

        <%= if @import.metadata && map_size(@import.metadata) > 0 do %>
          <div class="import-progress-metadata">
            <h2>{gettext("Details")}</h2>
            <dl class="import-progress-metadata-list">
              <%= if @import.metadata["file_count"] do %>
                <div class="import-progress-metadata-item">
                  <dt>{gettext("Files imported")}</dt>
                  <dd>{@import.metadata["file_count"]}</dd>
                </div>
              <% end %>
              <%= if @import.metadata["bundle_size"] do %>
                <div class="import-progress-metadata-item">
                  <dt>{gettext("Bundle size")}</dt>
                  <dd>{format_bytes(@import.metadata["bundle_size"])}</dd>
                </div>
              <% end %>
              <%= if @import.metadata["default_branch"] do %>
                <div class="import-progress-metadata-item">
                  <dt>{gettext("Default branch")}</dt>
                  <dd>{@import.metadata["default_branch"]}</dd>
                </div>
              <% end %>
            </dl>
          </div>
        <% end %>

        <div class="import-progress-timestamps">
          <%= if @import.started_at do %>
            <span>{gettext("Started: %{time}", time: format_datetime(@import.started_at))}</span>
          <% end %>
          <%= if @import.completed_at do %>
            <span>{gettext("Completed: %{time}", time: format_datetime(@import.completed_at))}</span>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp schedule_refresh(socket) do
    if import_running?(socket.assigns.import) do
      Process.send_after(self(), :refresh_import, @refresh_ms)
    end

    socket
  end

  defp import_running?(%ProjectImport{status: status}) when status in ["queued", "running"],
    do: true

  defp import_running?(_), do: false

  defp import_completed?(%ProjectImport{status: "completed"}), do: true
  defp import_completed?(_), do: false

  defp import_failed?(%ProjectImport{status: "failed"}), do: true
  defp import_failed?(_), do: false

  defp import_topic(import_id), do: "project_import:#{import_id}"

  defp stage_state(stage, %ProjectImport{} = import) do
    stages = ProjectImport.stages()
    stage_index = Enum.find_index(stages, &(&1 == stage)) || 0
    current_index = Enum.find_index(stages, &(&1 == import.stage)) || 0

    cond do
      import.status in ["completed", "rolled_back"] -> :done
      import.status == "failed" and stage_index == current_index -> :failed
      stage_index < current_index -> :done
      stage_index == current_index -> :in_progress
      true -> :pending
    end
  end

  defp status_label("queued"), do: gettext("Queued")
  defp status_label("running"), do: gettext("Running")
  defp status_label("completed"), do: gettext("Completed")
  defp status_label("failed"), do: gettext("Failed")
  defp status_label("rolled_back"), do: gettext("Rolled back")
  defp status_label(status), do: status

  defp stage_label("metadata"), do: gettext("Metadata")
  defp stage_label("git_data_clone"), do: gettext("Cloning repository")
  defp stage_label("validation"), do: gettext("Validation")
  defp stage_label("issue_migration"), do: gettext("Issue migration")
  defp stage_label("finalization"), do: gettext("Finalization")
  defp stage_label(stage), do: stage

  defp stage_state_label(:done), do: gettext("Done")
  defp stage_state_label(:in_progress), do: gettext("In progress")
  defp stage_state_label(:pending), do: gettext("Pending")
  defp stage_state_label(:failed), do: gettext("Failed")

  defp stage_icon(:done) do
    assigns = %{}

    ~H"""
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
      <path d="M20 6 9 17l-5-5" />
    </svg>
    """
  end

  defp stage_icon(:in_progress) do
    assigns = %{}

    ~H"""
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
      class="import-progress-spinner"
    >
      <path d="M21 12a9 9 0 1 1-6.219-8.56" />
    </svg>
    """
  end

  defp stage_icon(:pending) do
    assigns = %{}

    ~H"""
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
      <circle cx="12" cy="12" r="10" />
    </svg>
    """
  end

  defp stage_icon(:failed) do
    assigns = %{}

    ~H"""
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
      <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" />
      <path d="M12 9v4" /><path d="M12 17h.01" />
    </svg>
    """
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_bytes(_), do: "-"

  defp format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(_), do: "-"
end
