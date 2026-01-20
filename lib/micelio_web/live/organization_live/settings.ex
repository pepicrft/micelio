defmodule MicelioWeb.OrganizationLive.Settings do
  use MicelioWeb, :live_view

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.LLM
  alias MicelioWeb.PageMeta

  @impl true
  def mount(%{"organization_handle" => handle}, _session, socket) do
    case Accounts.get_organization_by_handle(handle) do
      {:ok, organization} ->
        if Authorization.authorize(:organization_update, socket.assigns.current_user, organization) ==
             :ok do
          account = organization.account
          {form, llm_default_options} = build_form(account, %{})

          socket =
            socket
            |> assign(:page_title, "Organization settings")
            |> PageMeta.assign(
              description: "Edit organization settings.",
              canonical_url: url(~p"/organizations/#{account.handle}/settings")
            )
            |> assign(:organization, organization)
            |> assign(:account, account)
            |> assign(:form, form)
            |> assign(:llm_default_options, llm_default_options)

          {:ok, socket}
        else
          {:ok,
           socket
           |> put_flash(:error, "You do not have access to this organization.")
           |> push_navigate(to: ~p"/#{organization.account.handle}")}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("validate", %{"account" => params}, socket) do
    {changeset, llm_default_options} =
      socket.assigns.account
      |> Accounts.change_account_settings(params)
      |> Map.put(:action, :validate)
      |> form_with_options(socket.assigns.account)

    {:noreply,
     assign(socket,
       form: to_form(changeset, as: :account),
       llm_default_options: llm_default_options
     )}
  end

  @impl true
  def handle_event("save", %{"account" => params}, socket) do
    if Authorization.authorize(
         :organization_update,
         socket.assigns.current_user,
         socket.assigns.organization
       ) ==
         :ok do
      case Accounts.update_account_settings(socket.assigns.account, params) do
        {:ok, account} ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization updated successfully!")
           |> push_navigate(to: ~p"/#{account.handle}")}

        {:error, changeset} ->
          {changeset, llm_default_options} =
            Map.put(changeset, :action, :validate)
            |> form_with_options(socket.assigns.account)

          {:noreply,
           assign(socket,
             form: to_form(changeset, as: :account),
             llm_default_options: llm_default_options
           )}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have access to this organization.")}
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
          Organization settings
          <:subtitle>
            <p>
              {@account.handle}
            </p>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="organization-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="project-form"
        >
          <div class="project-form-group">
            <.input
              field={@form[:llm_models]}
              type="select"
              label="Allowed LLM models"
              options={llm_model_options()}
              multiple
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">
              Limits which models can be selected on project settings.
            </p>
          </div>

          <div class="project-form-group">
            <.input
              field={@form[:llm_default_model]}
              type="select"
              label="Default LLM model"
              options={@llm_default_options}
              prompt="Use platform default"
              class="project-input"
              error_class="project-input project-input-error"
            />
            <p class="project-form-hint">
              New projects will start with this model unless overridden.
            </p>
          </div>

          <div class="project-form-actions">
            <button type="submit" class="project-button" id="organization-settings-submit">
              Save changes
            </button>
            <.link
              navigate={~p"/#{@account.handle}"}
              class="project-button project-button-secondary"
              id="organization-settings-cancel"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp build_form(account, attrs) do
    changeset = Accounts.change_account_settings(account, attrs)
    {changeset, llm_default_options} = form_with_options(changeset, account)
    {to_form(changeset, as: :account), llm_default_options}
  end

  defp form_with_options(changeset, account) do
    {changeset, llm_default_options(changeset, account)}
  end

  defp llm_model_options do
    LLM.project_model_options()
  end

  defp llm_default_options(changeset, account) do
    available = LLM.project_models()

    selected_models =
      case Ecto.Changeset.get_field(changeset, :llm_models) do
        models when is_list(models) and models != [] -> Enum.filter(models, &(&1 in available))
        _ -> LLM.project_models_for_account(account)
      end

    models = if selected_models == [], do: available, else: selected_models
    Enum.map(models, &{&1, &1})
  end
end
