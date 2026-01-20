defmodule MicelioWeb.PromptRequestLive.New do
  use MicelioWeb, :live_view

  alias Micelio.Authorization
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Projects
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"organization_handle" => org_handle, "project_handle" => project_handle}, _session, socket) do
    with {:ok, project, organization} <-
           Projects.get_project_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             project_handle
           ),
         :ok <- Authorization.authorize(:project_read, socket.assigns.current_user, project) do
      form =
        %PromptRequest{conversation: nil}
        |> PromptRequests.change_prompt_request()
        |> to_form(as: :prompt_request)

      socket =
        socket
        |> assign(:page_title, "New Prompt Request")
        |> PageMeta.assign(
          description: "Submit a prompt request for #{project.name}.",
          canonical_url:
            url(~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/new")
        )
        |> assign(:project, project)
        |> assign(:organization, organization)
        |> assign(:form, form)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Project not found or access denied.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("validate", %{"prompt_request" => params}, socket) do
    changeset =
      %PromptRequest{}
      |> PromptRequests.change_prompt_request(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :prompt_request))}
  end

  @impl true
  def handle_event("save", %{"prompt_request" => params}, socket) do
    case PromptRequests.create_prompt_request(params,
           project: socket.assigns.project,
           user: socket.assigns.current_user
         ) do
      {:ok, prompt_request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt request submitted.")
         |> push_navigate(
           to:
             ~p"/projects/#{socket.assigns.organization.account.handle}/#{socket.assigns.project.handle}/prompt-requests/#{prompt_request.id}"
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
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
      <div class="prompt-request-form-container">
        <.header>
          New prompt request
          <:subtitle>
            <p>Share the prompt, generated result, and full agent context.</p>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="prompt-request-form"
          phx-change="validate"
          phx-submit="save"
          class="prompt-request-form"
        >
          <div class="prompt-request-form-group">
            <.input
              field={@form[:title]}
              type="text"
              label="Title"
              placeholder="Summarize the request"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:model]}
              type="text"
              label="Model"
              placeholder="e.g., gpt-4.1"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:origin]}
              type="select"
              label="Contribution origin"
              options={origin_options()}
              prompt="Select origin"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:model_version]}
              type="text"
              label="Model version"
              placeholder="e.g., 2025-02-01"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:token_count]}
              type="number"
              label="Token count"
              placeholder="Tokens consumed during generation"
              min="0"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:generated_at]}
              type="datetime-local"
              label="Generation timestamp (UTC)"
              class="prompt-request-input"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:system_prompt]}
              type="textarea"
              label="System prompt"
              placeholder="System prompt used for the agent"
              class="prompt-request-input prompt-request-textarea"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:prompt]}
              type="textarea"
              label="User prompt"
              placeholder="Prompt submitted to the agent"
              class="prompt-request-input prompt-request-textarea"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:result]}
              type="textarea"
              label="Generated result"
              placeholder="Paste the generated result or diff"
              class="prompt-request-input prompt-request-textarea"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-group">
            <.input
              field={@form[:conversation]}
              type="textarea"
              label="Conversation history (JSON)"
              placeholder="{\"messages\": [{\"role\": \"user\", \"content\": \"...\"}]}"
              class="prompt-request-input prompt-request-textarea"
              error_class="prompt-request-input prompt-request-input-error"
            />
          </div>

          <div class="prompt-request-form-actions">
            <button type="submit" class="prompt-request-button" id="prompt-request-submit">
              Submit prompt request
            </button>
            <.link
              navigate={
                ~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests"
              }
              class="prompt-request-button prompt-request-button-secondary"
              id="prompt-request-cancel"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp origin_options do
    [
      {"AI-generated", "ai_generated"},
      {"AI-assisted", "ai_assisted"},
      {"Human", "human"}
    ]
  end
end
