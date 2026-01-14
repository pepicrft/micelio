defmodule MicelioWeb.ProjectLive.Edit do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.Projects

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
        if Authorization.authorize(:project_update, socket.assigns.current_user, project) == :ok do
          form =
            project
            |> Projects.change_project()
            |> to_form(as: :project)

          socket =
            socket
            |> assign(:page_title, "Edit Project")
            |> assign(:project, project)
            |> assign(:organization, organization)
            |> assign(:form, form)

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
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :project))}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    if Authorization.authorize(
         :project_update,
         socket.assigns.current_user,
         socket.assigns.project
       ) ==
         :ok do
      case Projects.update_project(socket.assigns.project, params) do
        {:ok, project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project updated successfully!")
           |> push_navigate(
             to: ~p"/projects/#{socket.assigns.organization.account.handle}/#{project.handle}"
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
      end
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
      <div class="project-form-container">
        <.header>
          Edit project
          <:subtitle>
            <p>
              {@organization.account.handle}/{@project.handle}
            </p>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="project-form"
          phx-change="validate"
          phx-submit="save"
          class="project-form"
        >
          <div class="project-form-group">
            <.input
              field={@form[:name]}
              type="text"
              label="Project name"
              placeholder="My Awesome Project"
              class="project-input"
              error_class="project-input project-input-error"
            />
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:handle]}
              type="text"
              label="Project handle"
              placeholder="awesome-project"
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">Handles appear in repository URLs.</p>
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:description]}
              type="textarea"
              label="Description"
              placeholder="Optional description"
              class="project-input project-textarea"
              error_class="project-input project-input-error"
            />
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:url]}
              type="url"
              label="URL"
              placeholder="https://example.com"
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">Optional homepage or repository URL.</p>
          </div>

          <div class="project-form-actions">
            <button type="submit" class="project-button" id="project-submit">
              Save changes
            </button>
            <.link
              navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}"}
              class="project-button project-button-secondary"
              id="project-cancel"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
