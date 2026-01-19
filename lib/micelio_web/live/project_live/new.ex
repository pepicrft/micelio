defmodule MicelioWeb.ProjectLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Projects
  alias Micelio.Projects.Project
  alias MicelioWeb.PageMeta

  @impl true
  def mount(_params, _session, socket) do
    organizations =
      Accounts.list_organizations_for_user_with_role(socket.assigns.current_user, "admin")

    default_org_id = organizations |> List.first() |> then(&(&1 && &1.id))

    form =
      %Project{}
      |> Projects.change_project(%{organization_id: default_org_id})
      |> to_form(as: :project)

    socket =
      socket
      |> assign(:page_title, "New Project")
      |> PageMeta.assign(
        description: "Create a new project.",
        canonical_url: url(~p"/projects/new")
      )
      |> assign(:organizations, organizations)
      |> assign(:organization_options, organization_options(organizations))
      |> assign(:form, form)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      %Project{}
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :project))}
  end

  @impl true
  def handle_event("save", %{"project" => params}, socket) do
    case find_organization(socket.assigns.organizations, params["organization_id"]) do
      nil ->
        changeset =
          %Project{}
          |> Projects.change_project(params)
          |> Ecto.Changeset.add_error(:organization_id, "is not available")
          |> Map.put(:action, :validate)

        {:noreply, assign(socket, form: to_form(changeset, as: :project))}

      organization ->
        if Authorization.authorize(:project_create, socket.assigns.current_user, organization) ==
             :ok do
          attrs = Map.put(params, "organization_id", organization.id)

          case Projects.create_project(attrs, user: socket.assigns.current_user) do
            {:ok, project} ->
              {:noreply,
               socket
               |> put_flash(:info, "Project created successfully!")
               |> push_navigate(
                 to: ~p"/projects/#{organization.account.handle}/#{project.handle}"
               )}

            {:error, changeset} ->
              {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
          end
        else
          {:noreply, put_flash(socket, :error, "You do not have access to this organization.")}
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
      <div class="project-form-container">
        <.header>
          New project
          <:subtitle>
            <p>Create a project under one of your organizations.</p>
          </:subtitle>
        </.header>

        <%= if Enum.empty?(@organizations) do %>
          <div class="projects-empty">
            <h2>No organizations available</h2>
            <p>You need to own an organization before you can create projects.</p>
            <.link
              navigate={~p"/organizations/new"}
              class="project-button"
              id="create-organization-from-projects"
            >
              Create an organization
            </.link>
          </div>
        <% else %>
          <.form
            for={@form}
            id="project-form"
            phx-change="validate"
            phx-submit="save"
            class="project-form"
          >
            <div class="project-form-group">
              <.input
                field={@form[:organization_id]}
                type="select"
                label="Organization"
                options={@organization_options}
                class="project-input"
                error_class="project-input project-input-error"
              />
            </div>

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
                field={@form[:visibility]}
                type="select"
                label="Visibility"
                options={visibility_options()}
                class="project-input"
                error_class="project-input project-input-error"
              />
              <p class="project-form-hint">Public projects are visible to everyone.</p>
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
                Create project
              </button>
              <.link
                navigate={~p"/projects"}
                class="project-button project-button-secondary"
                id="project-cancel"
              >
                Cancel
              </.link>
            </div>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp organization_options(organizations) do
    Enum.map(organizations, fn organization ->
      {organization.account.handle, organization.id}
    end)
  end

  defp visibility_options do
    [
      {"Private", "private"},
      {"Public", "public"}
    ]
  end

  defp find_organization(organizations, organization_id) do
    Enum.find(organizations, fn organization -> organization.id == organization_id end)
  end
end
