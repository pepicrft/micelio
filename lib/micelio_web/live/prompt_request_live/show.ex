defmodule MicelioWeb.PromptRequestLive.Show do
  use MicelioWeb, :live_view

  alias Micelio.AITokens
  alias Micelio.AITokens.TaskBudget
  alias Micelio.AITokens.TokenPool
  alias Micelio.Authorization
  alias Micelio.ContributionConfidence
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.PromptRequests.PromptSuggestion
  alias Micelio.Projects
  alias Micelio.Reputation
  alias MicelioWeb.PageMeta

  @impl true
  def mount(
        %{
          "organization_handle" => org_handle,
          "project_handle" => project_handle,
          "id" => id
        },
        _session,
        socket
      ) do
    with {:ok, project, organization} <-
           Projects.get_project_for_user_by_handle(
             socket.assigns.current_user,
             org_handle,
             project_handle
           ),
         :ok <- Authorization.authorize(:project_read, socket.assigns.current_user, project),
         prompt_request when not is_nil(prompt_request) <-
           PromptRequests.get_prompt_request_for_project(project, id) do
      diff_rows = build_diff_rows(prompt_request.prompt, prompt_request.result)

      reputation = Reputation.trust_score_for_user(prompt_request.user)
      lineage = PromptRequests.lineage(prompt_request)

      socket =
        socket
        |> assign(:page_title, prompt_request.title)
        |> PageMeta.assign(
          description: "Prompt request for #{project.name}.",
          canonical_url:
            url(
              ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
            )
        )
        |> assign(:project, project)
        |> assign(:organization, organization)
        |> assign(:prompt_request, prompt_request)
        |> assign_validation_feedback(prompt_request)
        |> assign(:attestation_status, PromptRequests.attestation_status(prompt_request))
        |> assign(:reputation, reputation)
        |> assign(:lineage, lineage)
        |> assign(:diff_rows, diff_rows)
        |> assign_suggestions(prompt_request)
        |> assign_validation_runs(prompt_request)
        |> assign_confidence_score(prompt_request)
        |> assign(:can_validate, can_validate?(socket.assigns.current_user, project))
        |> assign(:can_review, can_review?(socket.assigns.current_user, project))
        |> assign(:can_curate, can_curate?(socket.assigns.current_user, project))
        |> assign(:can_manage_budget, can_manage_budget?(socket.assigns.current_user, project))
        |> assign_task_budget_data(prompt_request, project)

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Prompt request not found or access denied.")
         |> push_navigate(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("run_validation", _params, socket) do
    if can_validate?(socket.assigns.current_user, socket.assigns.project) do
      case PromptRequests.run_validation_async(socket.assigns.prompt_request, self()) do
        {:ok, _pid} ->
          {:noreply, put_flash(socket, :info, "Validation started.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Unable to start validation: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to run validation.")}
    end
  end

  @impl true
  def handle_info({:validation_started, _run}, socket) do
    {:noreply, assign_validation_runs(socket, socket.assigns.prompt_request)}
  end

  @impl true
  def handle_info({:validation_finished, _prompt_request_id, {:ok, _run}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Validation passed.")
     |> assign_validation_runs(socket.assigns.prompt_request)
     |> refresh_prompt_request()}
  end

  @impl true
  def handle_info({:validation_finished, _prompt_request_id, {:error, _run}}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Validation failed.")
     |> assign_validation_runs(socket.assigns.prompt_request)
     |> refresh_prompt_request()}
  end

  @impl true
  def handle_event("validate_suggestion", %{"prompt_suggestion" => params}, socket) do
    changeset =
      %PromptSuggestion{}
      |> PromptRequests.change_prompt_suggestion(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, suggestion_form: to_form(changeset, as: :prompt_suggestion))}
  end

  @impl true
  def handle_event("save_suggestion", %{"prompt_suggestion" => params}, socket) do
    case PromptRequests.create_prompt_suggestion(
           socket.assigns.prompt_request,
           params,
           user: socket.assigns.current_user
         ) do
      {:ok, _suggestion} ->
        {:noreply,
         socket
         |> put_flash(:info, "Suggestion submitted.")
         |> assign_suggestions(socket.assigns.prompt_request)}

      {:error, changeset} ->
        {:noreply, assign(socket, suggestion_form: to_form(Map.put(changeset, :action, :validate)))}
    end
  end

  @impl true
  def handle_event("curate_prompt_request", _params, socket) do
    if socket.assigns.can_curate do
      case PromptRequests.curate_prompt_request(
             socket.assigns.prompt_request,
             socket.assigns.current_user
           ) do
        {:ok, _updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Prompt curated.")
           |> refresh_prompt_request()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Unable to curate this prompt.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to curate prompts.")}
    end
  end

  @impl true
  def handle_event("review_prompt_request", %{"status" => status}, socket) do
    if can_review?(socket.assigns.current_user, socket.assigns.project) do
      case parse_review_status(status) do
        {:ok, review_status} ->
          case PromptRequests.review_prompt_request(
                 socket.assigns.prompt_request,
                 socket.assigns.current_user,
                 review_status
               ) do
            {:ok, updated} ->
              reputation = Reputation.trust_score_for_user(socket.assigns.prompt_request.user)

              {:noreply,
               socket
               |> put_flash(:info, "Review status updated.")
               |> assign(:prompt_request, updated)
               |> assign(:reputation, reputation)}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Unable to update review status.")}
          end

        :error ->
          {:noreply, put_flash(socket, :error, "Invalid review status.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to review.")}
    end
  end

  @impl true
  def handle_event("validate_task_budget", %{"task_budget" => params}, socket) do
    changeset =
      socket.assigns.task_budget
      |> AITokens.change_task_budget(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, task_budget_form: to_form(changeset, as: :task_budget))}
  end

  @impl true
  def handle_event("save_task_budget", %{"task_budget" => params}, socket) do
    if socket.assigns.can_manage_budget do
      case AITokens.upsert_task_budget(socket.assigns.prompt_request, params) do
        {:ok, budget, pool} ->
          {:noreply,
           socket
           |> put_flash(:info, "Task budget updated.")
           |> assign_task_budget_state(budget, pool)}

        {:error, :insufficient_tokens} ->
          changeset =
            socket.assigns.task_budget
            |> AITokens.change_task_budget(params)
            |> Ecto.Changeset.add_error(:amount, "exceeds available tokens")
            |> Map.put(:action, :validate)

          {:noreply, assign(socket, task_budget_form: to_form(changeset, as: :task_budget))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, task_budget_form: to_form(Map.put(changeset, :action, :validate), as: :task_budget))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Unable to update task budget.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to manage budgets.")}
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
      <div class="prompt-request-show">
        <header class="prompt-request-show-header">
          <div class="prompt-request-breadcrumb">
            <.link navigate={~p"/projects"}>Projects</.link>
            <span>/</span>
            <.link navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}"}>
              {@project.name}
            </.link>
            <span>/</span>
            <.link
              navigate={~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests"}
            >
              Prompt Requests
            </.link>
            <span>/</span>
            <span>{@prompt_request.title}</span>
          </div>
          <div class="prompt-request-title">
            <h1>{@prompt_request.title}</h1>
            <div class="prompt-request-meta">
              <span class={"badge badge--caps prompt-request-origin prompt-request-origin-#{origin_value(@prompt_request.origin)}"}>
                {origin_label(@prompt_request.origin)}
              </span>
              <span class={"badge badge--caps prompt-request-review prompt-request-review-#{review_value(@prompt_request.review_status)}"}>
                Review: {review_label(@prompt_request.review_status)}
              </span>
              <span>Model: {format_model(@prompt_request.model)}</span>
              <span>Version: {format_model(@prompt_request.model_version)}</span>
              <span>Tokens: {format_token_count(@prompt_request.token_count)}</span>
              <span>Generated: {format_datetime(@prompt_request.generated_at)}</span>
              <span>
                Lag: {format_generation_lag(@prompt_request.generated_at, @prompt_request.inserted_at)}
              </span>
              <span>Submitted: {format_datetime(@prompt_request.inserted_at)}</span>
              <span>Attestation: {attestation_label(@attestation_status)}</span>
              <span>Submitted by {@prompt_request.user.email}</span>
              <span>Trust score: {@reputation.overall}</span>
              <span>Confidence: {format_confidence(@confidence_score)}</span>
              <%= if @prompt_request.curated_at do %>
                <span class="badge badge--caps prompt-request-curated">Curated</span>
              <% end %>
              <%= if @prompt_request.prompt_template do %>
                <span>Template: {@prompt_request.prompt_template.name}</span>
              <% end %>
              <%= if @prompt_request.session_id do %>
                <.link
                  navigate={
                    ~p"/projects/#{@organization.account.handle}/#{@project.handle}/sessions/#{@prompt_request.session_id}"
                  }
                  class="prompt-request-session-link"
                  id="prompt-request-session-link"
                >
                  View session
                </.link>
              <% end %>
            </div>
            <%= if @can_review do %>
              <div class="prompt-request-review-actions">
                <button
                  type="button"
                  class="prompt-request-button prompt-request-button-secondary"
                  phx-click="review_prompt_request"
                  phx-value-status="accepted"
                  id="prompt-request-accept"
                >
                  Accept
                </button>
                <button
                  type="button"
                  class="prompt-request-button prompt-request-button-secondary"
                  phx-click="review_prompt_request"
                  phx-value-status="rejected"
                  id="prompt-request-reject"
                >
                  Reject
                </button>
                <%= if @can_curate and is_nil(@prompt_request.curated_at) do %>
                  <button
                    type="button"
                    class="prompt-request-button prompt-request-button-secondary"
                    phx-click="curate_prompt_request"
                    id="prompt-request-curate"
                  >
                    Curate
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        </header>

        <section class="prompt-request-section prompt-request-transparency">
          <h2>Contribution Transparency</h2>
          <div class="prompt-request-transparency-grid">
            <div>
              <span class="prompt-request-label">Origin</span>
              <span>{origin_label(@prompt_request.origin)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Model</span>
              <span>{format_model(@prompt_request.model)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Model version</span>
              <span>{format_model(@prompt_request.model_version)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Token count</span>
              <span>{format_token_count(@prompt_request.token_count)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Confidence</span>
              <span>{format_confidence(@confidence_score)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Generated at</span>
              <span>{format_datetime(@prompt_request.generated_at)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Generation lag</span>
              <span>
                {format_generation_lag(@prompt_request.generated_at, @prompt_request.inserted_at)}
              </span>
            </div>
            <div>
              <span class="prompt-request-label">Submitted at</span>
              <span>{format_datetime(@prompt_request.inserted_at)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Template</span>
              <span>{prompt_template_label(@prompt_request)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Curated</span>
              <span>{curation_label(@prompt_request)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Execution time</span>
              <span>{format_duration_ms(@prompt_request.execution_duration_ms)}</span>
            </div>
            <div>
              <span class="prompt-request-label">Attestation</span>
              <span>{attestation_label(@attestation_status)}</span>
            </div>
          </div>
        </section>

        <section class="prompt-request-section">
          <h2>Prompt Lineage</h2>
          <%= if Enum.empty?(@lineage) do %>
            <p class="prompt-request-empty">No lineage recorded.</p>
          <% else %>
            <div class="prompt-request-lineage">
              <%= for ancestor <- @lineage do %>
                <.link
                  navigate={
                    ~p"/projects/#{@organization.account.handle}/#{@project.handle}/prompt-requests/#{ancestor.id}"
                  }
                  class="prompt-request-lineage-link"
                >
                  {ancestor.title}
                </.link>
              <% end %>
              <span class="prompt-request-lineage-current">{@prompt_request.title}</span>
            </div>
          <% end %>
        </section>

        <section class="prompt-request-section">
          <h2>Execution Environment</h2>
          <pre class="prompt-request-block">
{format_execution_environment(@prompt_request.execution_environment)}
          </pre>
        </section>

        <section class="prompt-request-section prompt-request-budget">
          <div class="prompt-request-section-header">
            <h2>Task budget</h2>
            <span class="prompt-request-budget-available">
              Available: {@token_pool_available} tokens
            </span>
          </div>
          <div class="prompt-request-budget-grid">
            <div>
              <span class="prompt-request-label">Pool balance</span>
              <span>{@token_pool.balance}</span>
            </div>
            <div>
              <span class="prompt-request-label">Pool reserved</span>
              <span>{@token_pool.reserved}</span>
            </div>
            <div>
              <span class="prompt-request-label">Allocated to this task</span>
              <span>{@task_budget.amount}</span>
            </div>
          </div>
          <%= if @can_manage_budget do %>
            <.form
              for={@task_budget_form}
              id="task-budget-form"
              phx-change="validate_task_budget"
              phx-submit="save_task_budget"
              class="prompt-request-budget-form"
            >
              <div class="prompt-request-form-group">
                <.input
                  field={@task_budget_form[:amount]}
                  type="number"
                  min="0"
                  step="1"
                  max={@task_budget_max}
                  label="Budget tokens"
                  class="prompt-request-input"
                  error_class="prompt-request-input prompt-request-input-error"
                />
              </div>
              <button
                type="submit"
                class="prompt-request-button prompt-request-button-secondary"
                id="task-budget-submit"
              >
                Update budget
              </button>
            </.form>
          <% else %>
            <p class="prompt-request-budget-note">
              Only project admins can allocate task budgets.
            </p>
          <% end %>
        </section>

        <section class="prompt-request-section">
          <h2>Prompt/Result Diff</h2>
          <div class="prompt-request-diff" id="prompt-request-diff">
            <div class="prompt-request-diff-header">
              <span>Prompt</span>
              <span>Result</span>
            </div>
            <div class="prompt-request-diff-body">
              <%= for row <- @diff_rows do %>
                <div class={"prompt-request-diff-row prompt-request-diff-#{row.type}"}>
                  <pre class="prompt-request-diff-cell">{row.left || ""}</pre>
                  <pre class="prompt-request-diff-cell">{row.right || ""}</pre>
                </div>
              <% end %>
            </div>
          </div>
        </section>

        <section class="prompt-request-section">
          <h2>Original Prompt</h2>
          <pre class="prompt-request-block">{@prompt_request.prompt}</pre>
        </section>

        <section class="prompt-request-section">
          <h2>System Prompt</h2>
          <pre class="prompt-request-block">{@prompt_request.system_prompt}</pre>
        </section>

        <section class="prompt-request-section">
          <h2>Conversation History</h2>
          <pre class="prompt-request-block">
{Jason.encode!(@prompt_request.conversation, pretty: true)}
          </pre>
        </section>

        <section class="prompt-request-section">
          <h2>Generated Result</h2>
          <pre class="prompt-request-block">{@prompt_request.result}</pre>
        </section>

        <%= if @validation_feedback do %>
          <section class="prompt-request-section">
            <h2>Validation Feedback</h2>
            <div class="prompt-request-feedback">
              <div class="prompt-request-feedback-summary">
                <span
                  class={
                    "prompt-request-feedback-status prompt-request-feedback-#{feedback_value(@validation_feedback, "status") || "failed"}"
                  }
                >
                  {String.capitalize(to_string(feedback_value(@validation_feedback, "status") || "failed"))}
                </span>
                <span>
                  Iteration: {feedback_value(@validation_feedback, "iteration") || @prompt_request.validation_iterations}
                </span>
                <%= if quality_score = feedback_value(@validation_feedback, "quality_score") do %>
                  <span>Quality score: {format_feedback_score(quality_score)}</span>
                <% end %>
                <%= if threshold = feedback_value(@validation_feedback, "quality_threshold") do %>
                  <%= if minimum = feedback_value(threshold, "minimum") do %>
                    <span>Minimum: {format_feedback_minimum(minimum)}</span>
                  <% end %>
                <% end %>
              </div>
              <p class="prompt-request-feedback-message">
                {feedback_value(@validation_feedback, "summary") || "Validation failed."}
              </p>

              <%= if quality_scores = feedback_value(@validation_feedback, "quality_scores") do %>
                <div class="prompt-request-feedback-grid">
                  <%= for {label, score} <- Enum.sort(quality_scores) do %>
                    <div class="prompt-request-feedback-card">
                      <span class="prompt-request-feedback-label">{format_quality_label(label)}</span>
                      <span class="prompt-request-feedback-score">{format_feedback_score(score)}</span>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if failures = feedback_value(@validation_feedback, "failures") do %>
                <div class="prompt-request-feedback-list">
                  <h3>Failures</h3>
                  <%= for failure <- failures do %>
                    <div class="prompt-request-feedback-failure">
                      <div class="prompt-request-feedback-failure-header">
                        <span>
                          {feedback_value(failure, "label") ||
                            feedback_value(failure, "stage") || "Failure"}
                        </span>
                        <%= if check_id = feedback_value(failure, "check_id") do %>
                          <span class="prompt-request-feedback-chip">{check_id}</span>
                        <% end %>
                        <%= if exit_code = feedback_value(failure, "exit_code") do %>
                          <span>Exit {exit_code}</span>
                        <% end %>
                      </div>
                      <%= if command = feedback_value(failure, "command") do %>
                        <div class="prompt-request-feedback-mono">
                          Command: {format_command(command, feedback_value(failure, "args") || [])}
                        </div>
                      <% end %>
                      <%= if reason = feedback_value(failure, "reason") do %>
                        <div class="prompt-request-feedback-note">{reason}</div>
                      <% end %>
                      <%= if stdout = feedback_value(failure, "stdout") do %>
                        <pre class="prompt-request-feedback-output">{stdout}</pre>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <%= if fixes = feedback_value(@validation_feedback, "suggested_fixes") do %>
                <div class="prompt-request-feedback-list">
                  <h3>Suggested fixes</h3>
                  <ul class="prompt-request-feedback-suggestions">
                    <%= for fix <- fixes do %>
                      <li>{fix}</li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>

        <section class="prompt-request-section">
          <div class="prompt-request-section-header">
            <h2>Validation Runs</h2>
            <%= if @can_validate do %>
              <button
                type="button"
                class="prompt-request-button prompt-request-button-secondary"
                phx-click="run_validation"
                id="prompt-request-run-validation"
              >
                Run validation
              </button>
            <% end %>
          </div>
          <div class="prompt-request-validation">
            <%= if Enum.empty?(@validation_runs) do %>
              <p class="prompt-request-empty">No validation runs yet.</p>
            <% else %>
              <%= for run <- @validation_runs do %>
                <div class="prompt-request-validation-run">
                  <div class="prompt-request-validation-summary">
                    <span class={"prompt-request-validation-status prompt-request-validation-#{run.status}"}>
                      {status_label(run.status)}
                    </span>
                    <span>Provider: {run.provider || "n/a"}</span>
                    <span>Duration: {format_duration_ms(metric_value(run.metrics, "duration_ms"))}</span>
                    <span>Coverage delta: {format_coverage(run.coverage_delta)}</span>
                  </div>
                  <div class="prompt-request-validation-details">
                    <span>
                      Resources: {format_resource_usage(run.resource_usage)}
                    </span>
                    <span>
                      Checks: {format_check_count(run.check_results["checks"])}
                    </span>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </section>

        <section class="prompt-request-section">
          <h2>Prompt Improvement Suggestions</h2>
          <div class="prompt-request-suggestions">
            <%= if Enum.empty?(@suggestions) do %>
              <p class="prompt-request-empty">No suggestions yet.</p>
            <% else %>
              <%= for suggestion <- @suggestions do %>
                <div class="prompt-request-suggestion">
                  <p>{suggestion.suggestion}</p>
                  <span>By {suggestion.user.email}</span>
                </div>
              <% end %>
            <% end %>
          </div>

          <.form
            for={@suggestion_form}
            id="prompt-suggestion-form"
            phx-change="validate_suggestion"
            phx-submit="save_suggestion"
            class="prompt-request-suggestion-form"
          >
            <div class="prompt-request-form-group">
              <.input
                field={@suggestion_form[:suggestion]}
                type="textarea"
                label="Add a suggestion"
                placeholder="Offer a prompt improvement idea"
                class="prompt-request-input prompt-request-textarea"
                error_class="prompt-request-input prompt-request-input-error"
              />
            </div>
            <div class="prompt-request-form-actions">
              <button type="submit" class="prompt-request-button" id="prompt-suggestion-submit">
                Submit suggestion
              </button>
            </div>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp assign_suggestions(socket, prompt_request) do
    suggestions = PromptRequests.list_prompt_suggestions(prompt_request)
    form =
      %PromptSuggestion{}
      |> PromptRequests.change_prompt_suggestion()
      |> to_form(as: :prompt_suggestion)

    socket
    |> assign(:suggestions, suggestions)
    |> assign(:suggestion_form, form)
  end

  defp assign_validation_runs(socket, prompt_request) do
    socket
    |> assign(:validation_runs, PromptRequests.list_validation_runs(prompt_request))
  end

  defp assign_task_budget_data(socket, prompt_request, project) do
    pool =
      case AITokens.get_token_pool_by_project(project.id) do
        %TokenPool{} = pool -> pool
        nil -> %TokenPool{project_id: project.id, balance: 0, reserved: 0}
      end

    budget =
      case AITokens.get_task_budget_for_prompt_request(prompt_request) do
        %TaskBudget{} = budget -> budget
        nil -> %TaskBudget{prompt_request_id: prompt_request.id, amount: 0}
      end

    socket
    |> assign_task_budget_state(budget, pool)
  end

  defp assign_task_budget_state(socket, budget, pool) do
    available = max(pool.balance - pool.reserved, 0)
    budget_amount = budget.amount || 0
    max_budget = available + budget_amount
    form = to_form(AITokens.change_task_budget(budget, %{}), as: :task_budget)

    socket
    |> assign(:task_budget, budget)
    |> assign(:token_pool, pool)
    |> assign(:token_pool_available, available)
    |> assign(:task_budget_max, max_budget)
    |> assign(:task_budget_form, form)
  end

  defp can_validate?(user, project) do
    Authorization.authorize(:project_update, user, project) == :ok
  end

  defp can_review?(user, project) do
    Authorization.authorize(:project_update, user, project) == :ok
  end

  defp can_manage_budget?(user, project) do
    Authorization.authorize(:project_update, user, project) == :ok
  end

  defp can_curate?(user, project) do
    Authorization.authorize(:project_update, user, project) == :ok
  end

  defp refresh_prompt_request(socket) do
    case PromptRequests.get_prompt_request_for_project(
           socket.assigns.project,
           socket.assigns.prompt_request.id
         ) do
      %PromptRequest{} = prompt_request ->
        socket
        |> assign(:prompt_request, prompt_request)
        |> assign_validation_feedback(prompt_request)
        |> assign(:attestation_status, PromptRequests.attestation_status(prompt_request))
        |> assign(:reputation, Reputation.trust_score_for_user(prompt_request.user))
        |> assign_confidence_score(prompt_request)

      _ ->
        socket
    end
  end

  defp status_label(:passed), do: "Passed"
  defp status_label(:failed), do: "Failed"
  defp status_label(:running), do: "Running"
  defp status_label(:pending), do: "Pending"
  defp status_label(other), do: to_string(other)

  defp format_duration_ms(nil), do: "n/a"

  defp format_duration_ms(milliseconds) when is_integer(milliseconds) do
    seconds = milliseconds / 1000
    :io_lib.format("~.2fs", [seconds]) |> IO.iodata_to_binary()
  end

  defp format_model(nil), do: "n/a"
  defp format_model(""), do: "n/a"
  defp format_model(value), do: value

  defp format_token_count(nil), do: "n/a"
  defp format_token_count(value) when is_integer(value), do: Integer.to_string(value)

  defp format_confidence(%ContributionConfidence.Score{overall: overall, label: label}) do
    "#{overall} (#{label})"
  end

  defp format_confidence(_score), do: "n/a"

  defp assign_validation_feedback(socket, %PromptRequest{} = prompt_request) do
    assign(socket, :validation_feedback, PromptRequests.format_validation_feedback(prompt_request.validation_feedback))
  end

  defp assign_confidence_score(socket, %PromptRequest{} = prompt_request) do
    score =
      PromptRequests.confidence_score(prompt_request,
        validation_runs: socket.assigns[:validation_runs] || [],
        reputation: socket.assigns[:reputation]
      )

    assign(socket, :confidence_score, score)
  end

  defp feedback_value(%{} = feedback, key) when is_atom(key) do
    Map.get(feedback, key) || Map.get(feedback, Atom.to_string(key))
  end

  defp feedback_value(%{} = feedback, key) when is_binary(key) do
    case Map.get(feedback, key) do
      nil ->
        case safe_existing_atom(key) do
          {:ok, atom_key} -> Map.get(feedback, atom_key)
          :error -> nil
        end

      value ->
        value
    end
  end

  defp feedback_value(_feedback, _key), do: nil

  defp safe_existing_atom(key) do
    try do
      {:ok, String.to_existing_atom(key)}
    rescue
      ArgumentError -> :error
    end
  end

  defp format_feedback_score(score) when is_number(score), do: "#{score}/100"
  defp format_feedback_score(_score), do: "n/a"

  defp format_feedback_minimum(nil), do: nil
  defp format_feedback_minimum(value) when is_number(value), do: "#{value}/100"
  defp format_feedback_minimum(value), do: to_string(value)

  defp format_quality_label(label) when is_atom(label), do: label |> Atom.to_string() |> format_quality_label()

  defp format_quality_label(label) when is_binary(label) do
    label
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_quality_label(_label), do: "Score"

  defp format_command(command, args) do
    [command | List.wrap(args)]
    |> Enum.map(&to_string/1)
    |> Enum.join(" ")
  end

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp format_execution_environment(nil), do: "n/a"

  defp format_execution_environment(environment) when is_map(environment) do
    Jason.encode!(environment, pretty: true)
  end

  defp format_execution_environment(environment) when is_binary(environment), do: environment

  defp format_generation_lag(%DateTime{} = generated_at, %DateTime{} = submitted_at) do
    diff_seconds = DateTime.diff(submitted_at, generated_at, :second)

    cond do
      diff_seconds < 0 ->
        "n/a"

      diff_seconds < 60 ->
        "<1m"

      diff_seconds < 3600 ->
        "#{div(diff_seconds, 60)}m"

      diff_seconds < 86_400 ->
        hours = div(diff_seconds, 3600)
        minutes = div(rem(diff_seconds, 3600), 60)
        "#{hours}h #{minutes}m"

      true ->
        days = div(diff_seconds, 86_400)
        hours = div(rem(diff_seconds, 86_400), 3600)
        "#{days}d #{hours}h"
    end
  end

  defp format_generation_lag(_, _), do: "n/a"

  defp prompt_template_label(%PromptRequest{prompt_template: nil}), do: "n/a"

  defp prompt_template_label(%PromptRequest{prompt_template: template}) do
    template.name
  end

  defp curation_label(%PromptRequest{curated_at: nil}), do: "Not curated"

  defp curation_label(%PromptRequest{} = prompt_request) do
    curator =
      case prompt_request.curated_by do
        nil -> "Unknown"
        user -> user.email
      end

    "Curated by #{curator}"
  end

  defp origin_label(origin), do: PromptRequest.origin_label(origin)

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: "unknown"

  defp review_label(:accepted), do: "Accepted"
  defp review_label(:rejected), do: "Rejected"
  defp review_label(:pending), do: "Pending"
  defp review_label(nil), do: "Pending"

  defp review_value(:accepted), do: "accepted"
  defp review_value(:rejected), do: "rejected"
  defp review_value(:pending), do: "pending"
  defp review_value(nil), do: "pending"

  defp parse_review_status("accepted"), do: {:ok, :accepted}
  defp parse_review_status("rejected"), do: {:ok, :rejected}
  defp parse_review_status("pending"), do: {:ok, :pending}
  defp parse_review_status(_), do: :error

  defp attestation_label(:verified), do: "Verified"
  defp attestation_label(:invalid), do: "Invalid"
  defp attestation_label(:missing), do: "Missing"

  defp format_coverage(nil), do: "n/a"

  defp format_coverage(delta) when is_number(delta) do
    percent = delta * 100
    :io_lib.format("~.2f%%", [percent]) |> IO.iodata_to_binary()
  end

  defp format_resource_usage(resource_usage) when map_size(resource_usage) == 0, do: "n/a"

  defp format_resource_usage(resource_usage) do
    cpu = Map.get(resource_usage, "cpu_seconds") || Map.get(resource_usage, :cpu_seconds)
    memory = Map.get(resource_usage, "memory_mb") || Map.get(resource_usage, :memory_mb)

    [
      format_resource_value("CPU", cpu, "s"),
      format_resource_value("Memory", memory, "MB")
    ]
    |> Enum.reject(&(&1 == nil))
    |> Enum.join(" · ")
    |> case do
      "" -> "n/a"
      value -> value
    end
  end

  defp format_resource_value(_label, nil, _unit), do: nil

  defp format_resource_value(label, value, unit) when is_number(value) do
    formatted = :io_lib.format("~.2f", [value]) |> IO.iodata_to_binary()
    "#{label}: #{formatted}#{unit}"
  end

  defp format_check_count(nil), do: "n/a"

  defp format_check_count(checks) when is_list(checks) do
    "#{length(checks)} total"
  end

  defp metric_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp build_diff_rows(left, right) do
    left_lines = split_lines(left)
    right_lines = split_lines(right)

    left_lines
    |> List.myers_difference(right_lines)
    |> Enum.flat_map(fn
      {:eq, lines} ->
        Enum.map(lines, &%{left: &1, right: &1, type: :eq})

      {:del, lines} ->
        Enum.map(lines, &%{left: &1, right: nil, type: :del})

      {:ins, lines} ->
        Enum.map(lines, &%{left: nil, right: &1, type: :ins})
    end)
  end

  defp split_lines(nil), do: [""]

  defp split_lines(text) do
    text
    |> String.split("\n", trim: false)
  end
end
