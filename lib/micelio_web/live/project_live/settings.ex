defmodule MicelioWeb.RepositoryLive.Settings do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.LLM
  alias Micelio.Projects
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"account" => account_handle, "repository" => repository_handle}, _session, socket) do
    case Projects.get_project_for_user_by_handle(
           socket.assigns.current_user,
           account_handle,
           repository_handle
         ) do
      {:ok, repository, organization} ->
        if Authorization.authorize(:project_update, socket.assigns.current_user, repository) ==
             :ok do
          form =
            repository
            |> Projects.change_project_settings(%{}, organization: organization)
            |> to_form(as: :repository)

          socket =
            socket
            |> assign(:page_title, "Repository settings")
            |> PageMeta.assign(
              description: "Edit repository settings.",
              canonical_url:
                url(~p"/#{organization.account.handle}/#{repository.handle}/settings")
            )
            |> assign(:repository, repository)
            |> assign(:organization, organization)
            |> assign(:form, form)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this repository.")
           |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Repository not found.")
         |> push_navigate(to: ~p"/#{account_handle}/#{repository_handle}")}
    end
  end

  @impl true
  def handle_event("validate", %{"repository" => params}, socket) do
    changeset =
      socket.assigns.repository
      |> Projects.change_project_settings(params, organization: socket.assigns.organization)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :repository))}
  end

  @impl true
  def handle_event("save", %{"repository" => params}, socket) do
    if Authorization.authorize(
         :project_update,
         socket.assigns.current_user,
         socket.assigns.repository
       ) ==
         :ok do
      case Projects.update_project_settings(socket.assigns.repository, params,
             user: socket.assigns.current_user,
             organization: socket.assigns.organization
           ) do
        {:ok, repository} ->
          {:noreply,
           socket
           |> put_flash(:info, "Repository updated successfully!")
           |> push_navigate(
             to: ~p"/#{socket.assigns.organization.account.handle}/#{repository.handle}"
           )}

        {:error, changeset} ->
          {:noreply,
           assign(socket,
             form: to_form(Map.put(changeset, :action, :validate), as: :repository)
           )}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this repository.")}
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
          Repository settings
          <:subtitle>
            <p>
              {@organization.account.handle}/{@repository.handle}
            </p>
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/settings/import"}
              class="project-button project-button-secondary"
              id="repository-import-link"
            >
              Import
            </.link>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@repository.handle}/settings/webhooks"}
              class="project-button project-button-secondary"
              id="repository-webhooks-link"
            >
              Webhooks
            </.link>
          </:actions>
        </.header>

        <.form
          for={@form}
          id="repository-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="project-form"
        >
          <div class="project-form-group">
            <.input
              field={@form[:name]}
              type="text"
              label="Project name"
              placeholder="My Project"
              class="project-input"
              error_class="project-input project-input-error"
            />
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
            <p class="project-form-hint">Public repositories are visible to everyone.</p>
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:llm_model]}
              type="select"
              label="Default LLM model"
              options={llm_model_options(@organization)}
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">
              Sets the default model for agent runs and automated workflows.
            </p>
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:protect_main_branch]}
              type="checkbox"
              label="Protect main branch"
              class="project-checkbox"
            />
            <p class="project-form-hint">
              Blocks direct session lands to main, so changes must land via a merge workflow.
            </p>
          </div>

          <div class="project-form-actions">
            <button type="submit" class="project-button" id="repository-settings-submit">
              Save changes
            </button>
            <.link
              navigate={~p"/#{@organization.account.handle}/#{@repository.handle}"}
              class="project-button project-button-secondary"
              id="repository-settings-cancel"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp visibility_options do
    [
      {"Private", "private"},
      {"Public", "public"}
    ]
  end

  defp llm_model_options(%{account: account}) do
    LLM.project_model_options_for_account(account)
  end
end
