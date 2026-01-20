defmodule MicelioWeb.ProjectLive.Import do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Projects
  alias Micelio.Projects.ProjectImport
  alias MicelioWeb.PageMeta

  @refresh_ms 2_000

  @impl true
  def mount(%{"account" => account_handle, "project" => project_handle}, _session, socket) do
    case Projects.get_project_for_user_by_handle(
           socket.assigns.current_user,
           account_handle,
           project_handle
         ) do
      {:ok, project, organization} ->
        if Authorization.authorize(:project_update, socket.assigns.current_user, project) ==
             :ok do
          import = Projects.get_latest_project_import(project)

          socket =
            socket
            |> assign(:page_title, "Project import")
            |> PageMeta.assign(
              description: "Import project data from another git forge.",
              canonical_url:
                url(~p"/#{organization.account.handle}/#{project.handle}/settings/import")
            )
            |> assign(:project, project)
            |> assign(:organization, organization)
            |> assign(:import, import)
            |> assign(:form, import_form(project, socket.assigns.current_user))
            |> assign(:stages, ProjectImport.stages())

          {:ok, schedule_refresh(socket)}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this project.")
           |> push_navigate(to: ~p"/#{account_handle}/#{project_handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found.")
         |> push_navigate(to: ~p"/#{account_handle}/#{project_handle}")}
    end
  end

  @impl true
  def handle_event("validate", %{"project_import" => params}, socket) do
    params = enrich_params(params, socket.assigns.project, socket.assigns.current_user)

    changeset =
      %ProjectImport{}
      |> Projects.change_project_import(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :project_import))}
  end

  @impl true
  def handle_event("save", %{"project_import" => params}, socket) do
    params = enrich_params(params, socket.assigns.project, socket.assigns.current_user)

    case Projects.start_project_import(
           socket.assigns.project,
           socket.assigns.current_user,
           params
         ) do
      {:ok, import} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project import started.")
         |> assign(:import, import)
         |> assign(:form, import_form(socket.assigns.project, socket.assigns.current_user))
         |> schedule_refresh()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Import failed to start: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("rollback", _params, socket) do
    case socket.assigns.import do
      %ProjectImport{} = import ->
        case Projects.rollback_project_import(import) do
          {:ok, updated_import} ->
            {:noreply,
             socket
             |> put_flash(:info, "Import rollback completed.")
             |> assign(:import, updated_import)}

          {:error, reason} ->
            {:noreply,
             socket
             |> put_flash(:error, "Import rollback failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_import, socket) do
    import = Projects.get_latest_project_import(socket.assigns.project)

    socket =
      socket
      |> assign(:import, import)
      |> schedule_refresh()

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="project-form-container">
        <.header>
          Project import
          <:subtitle>
            <p>
              {@organization.account.handle}/{@project.handle}
            </p>
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@project.handle}/settings"}
              class="project-button project-button-secondary"
              id="project-settings-link"
            >
              Settings
            </.link>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@project.handle}/settings/webhooks"}
              class="project-button project-button-secondary"
              id="project-import-webhooks-link"
            >
              Webhooks
            </.link>
          </:actions>
        </.header>

        <.form
          for={@form}
          id="project-import-form"
          phx-change="validate"
          phx-submit="save"
          class="project-form"
        >
          <div class="project-form-group">
            <.input
              field={@form[:source_url]}
              type="text"
              label="Project URL"
              placeholder="https://github.com/org/repo"
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">
              Imports the project history and lands the latest state as a new session.
            </p>
          </div>

          <div class="project-form-actions">
            <button
              type="submit"
              class="project-button"
              id="project-import-submit"
              disabled={import_running?(@import)}
            >
              Start import
            </button>
          </div>
        </.form>

        <%= if @import do %>
          <div class="project-form-group">
            <label>Latest import</label>
            <p class="project-form-hint">
              Status: {@import.status} / Stage: {@import.stage}
            </p>
            <ul>
              <%= for stage <- @stages do %>
                <li><%= stage_label(stage) %> — <%= stage_state(stage, @import) %></li>
              <% end %>
            </ul>
            <%= if @import.error_message do %>
              <p class="project-form-hint">Error: {@import.error_message}</p>
            <% end %>
            <%= if rollback_available?(@import) do %>
              <button
                type="button"
                class="project-button project-button-secondary"
                id="project-import-rollback"
                phx-click="rollback"
              >
                Roll back import
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp import_form(project, user, params \\ %{}) do
    params = enrich_params(params, project, user)

    %ProjectImport{}
    |> Projects.change_project_import(params)
    |> to_form(as: :project_import)
  end

  defp enrich_params(params, project, user) do
    params
    |> Map.put_new("project_id", project.id)
    |> Map.put_new("user_id", user.id)
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

  defp rollback_available?(%ProjectImport{} = import) do
    previous_head = Map.get(import.metadata || %{}, "previous_head")

    import.status in ["failed", "completed"] and is_binary(previous_head) and
      import.status != "rolled_back"
  end

  defp rollback_available?(_), do: false

  defp stage_state(stage, %ProjectImport{} = import) do
    stages = ProjectImport.stages()
    stage_index = Enum.find_index(stages, &(&1 == stage)) || 0
    current_index = Enum.find_index(stages, &(&1 == import.stage)) || 0

    cond do
      import.status in ["completed", "rolled_back"] -> "done"
      stage_index < current_index -> "done"
      stage_index == current_index -> "in progress"
      true -> "pending"
    end
  end

  defp stage_label("metadata"), do: "Project metadata"
  defp stage_label("git_data_clone"), do: "Git data clone"
  defp stage_label("validation"), do: "Project validation"
  defp stage_label("issue_migration"), do: "Issue/PR migration"
  defp stage_label("finalization"), do: "Finalization"
  defp stage_label(stage), do: stage
end
