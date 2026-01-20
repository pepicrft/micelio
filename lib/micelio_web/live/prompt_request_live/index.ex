defmodule MicelioWeb.PromptRequestLive.Index do
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
      prompt_requests = PromptRequests.list_prompt_requests_for_project(project)

      socket =
        socket
        |> assign(:page_title, "Prompt Requests")
        |> PageMeta.assign(
          description: "Prompt requests for #{project.name}.",
          canonical_url:
            url(~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests")
        )
        |> assign(:project, project)
        |> assign(:organization, organization)
        |> assign(:prompt_requests, prompt_requests)

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
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="prompt-requests-container">
        <.header>
          Prompt Requests
          <:subtitle>
            <div class="prompt-requests-subtitle">
              For {@organization.account.handle}/{@project.handle}
            </div>
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests/new"}
              class="prompt-request-button"
              id="new-prompt-request"
            >
              New prompt request
            </.link>
          </:actions>
        </.header>

        <%= if Enum.empty?(@prompt_requests) do %>
          <div class="prompt-requests-empty">
            <h2>No prompt requests yet</h2>
            <p>Start a contribution by sharing the prompt and the generated result.</p>
          </div>
        <% else %>
          <div class="prompt-requests-list" id="prompt-request-list">
            <%= for prompt_request <- @prompt_requests do %>
              <.link
                navigate={
                  ~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests/#{prompt_request.id}"
                }
                class="prompt-request-card"
                id={"prompt-request-#{prompt_request.id}"}
              >
                <div class="prompt-request-card-title">
                  {prompt_request.title}
                  <span
                    class={"badge badge--caps prompt-request-origin prompt-request-origin-#{origin_value(prompt_request.origin)}"}
                  >
                    {origin_label(prompt_request.origin)}
                  </span>
                </div>
                <div class="prompt-request-card-meta">
                  <span>Model: {format_model(prompt_request.model)}</span>
                  <span>Version: {format_model(prompt_request.model_version)}</span>
                  <span>Tokens: {format_token_count(prompt_request.token_count)}</span>
                  <span>Submitted by {prompt_request.user.email}</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp origin_label(origin), do: PromptRequest.origin_label(origin)

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: "unknown"

  defp format_model(nil), do: "n/a"
  defp format_model(""), do: "n/a"
  defp format_model(value), do: value

  defp format_token_count(nil), do: "n/a"
  defp format_token_count(value) when is_integer(value), do: Integer.to_string(value)
end
