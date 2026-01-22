defmodule MicelioWeb.PromptRequestLiveTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.AITokens.TaskBudget
  alias Micelio.PromptRequests
  alias Micelio.Projects
  alias Micelio.Repo
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun

  defp login_user(conn, user) do
    Plug.Test.init_test_session(conn, %{user_id: user.id})
  end

  defp setup_project do
    {:ok, user} = Accounts.get_or_create_user_by_email("prompt-live@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "prompt-live-org",
        name: "Prompt Live Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "prompt-live-project",
        name: "Prompt Live Project",
        organization_id: organization.id
      })

    {user, organization, project}
  end

  test "lists prompt requests and creates a new one", %{conn: conn} do
    {user, organization, project} = setup_project()

    conn = login_user(conn, user)
    {:ok, view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests")

    assert has_element?(view, "#new-prompt-request")

    {:ok, form_view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/new")

    conversation_json = "{\"messages\":[{\"role\":\"user\",\"content\":\"Ship it\"}]}"
    generated_at = "2025-02-10T12:00:00Z"

    form =
      form(form_view, "#prompt-request-form",
        prompt_request: %{
          title: "Ship prompt request",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: "ai_generated",
          token_count: 1200,
          generated_at: generated_at,
          system_prompt: "System",
          prompt: "Do the thing",
          result: "Diff output",
          conversation: conversation_json
        }
      )

    render_submit(form)

    [prompt_request] = PromptRequests.list_prompt_requests_for_project(project)

    {:ok, submitted_at, _} = DateTime.from_iso8601("2025-02-10T12:10:00Z")

    prompt_request
    |> Ecto.Changeset.change(%{inserted_at: submitted_at})
    |> Repo.update!()

    assert_redirect(
      form_view,
      ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
    )

    {:ok, list_view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests")

    assert has_element?(list_view, "#prompt-request-#{prompt_request.id}")
    assert render(list_view) =~ "AI-generated"
    assert render(list_view) =~ "Model: gpt-4.1"
    assert render(list_view) =~ "Tokens: 1200"
    assert render(list_view) =~ "Generated: 2025-02-10 12:00:00 UTC"
    assert render(list_view) =~ "Submitted: 2025-02-10 12:10:00 UTC"
    assert render(list_view) =~ "Lag: 10m"
    assert render(list_view) =~ "Attestation: Verified"
  end

  test "loads approved prompt templates into the form", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, template} =
      PromptRequests.create_prompt_template(
        %{
          name: "Bug fix",
          description: "Fixes a reported issue",
          category: "Bug",
          system_prompt: "System prompt for bug fixes",
          prompt: "Investigate and fix the issue"
        },
        created_by: user
      )

    {:ok, _} = PromptRequests.approve_prompt_template(template, user)

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/new")

    form =
      form(view, "#prompt-request-form",
        prompt_request: %{
          prompt_template_id: template.id
        }
      )

    render_change(form)

    view
    |> element("#prompt-request-load-template")
    |> render_click()

    html = render(view)
    assert html =~ "System prompt for bug fixes"
    assert html =~ "Investigate and fix the issue"
  end

  test "redirects to prompt request show when validation fails on submit", %{conn: conn} do
    {user, organization, project} = setup_project()

    previous_flow = Application.get_env(:micelio, :prompt_request_flow)

    Application.put_env(:micelio, :prompt_request_flow,
      validation_enabled: true,
      validation_async: false,
      validation_opts: [
        provider_module: Micelio.TestValidationProvider,
        executor: Micelio.TestFailingValidationExecutor,
        plan_attrs: %{
          provider: "aws",
          image: "micelio/validation-runner:latest",
          cpu_cores: 2,
          memory_mb: 1024,
          disk_gb: 10,
          ttl_seconds: 1200,
          network: "egress"
        }
      ]
    )

    on_exit(fn ->
      if previous_flow do
        Application.put_env(:micelio, :prompt_request_flow, previous_flow)
      else
        Application.delete_env(:micelio, :prompt_request_flow)
      end
    end)

    conn = login_user(conn, user)

    {:ok, form_view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/new")

    conversation_json = "{\"messages\":[{\"role\":\"user\",\"content\":\"Ship it\"}]}"

    form =
      form(form_view, "#prompt-request-form",
        prompt_request: %{
          title: "Failing validation",
          origin: "human",
          system_prompt: "System",
          prompt: "Do the thing",
          result: "Diff output",
          conversation: conversation_json
        }
      )

    render_submit(form)

    [prompt_request] = PromptRequests.list_prompt_requests_for_project(project)

    feedback = PromptRequests.format_validation_feedback(prompt_request.validation_feedback)
    assert feedback["summary"] =~ "Validation failed"

    assert_redirect(
      form_view,
      ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
    )
  end

  test "renders structured validation feedback", %{conn: conn} do
    {user, organization, project} = setup_project()
    generated_at = DateTime.utc_now() |> DateTime.add(-600, :second) |> DateTime.truncate(:second)

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Structured feedback",
          prompt: "Ship it",
          result: "Done",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 320,
          generated_at: generated_at,
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Ship it"}]}
        },
        project: project,
        user: user
      )

    feedback = %{
      "summary" => "Validation failed: quality score 72/100 below minimum 80.",
      "status" => "failed",
      "iteration" => 2,
      "quality_score" => 72,
      "quality_threshold" => %{"minimum" => 80},
      "quality_scores" => %{"build" => 85, "test" => 60},
      "failures" => [
        %{
          "check_id" => "test",
          "label" => "Tests",
          "exit_code" => 1,
          "command" => "mix",
          "args" => ["test"],
          "stdout" => "Failure"
        }
      ],
      "suggested_fixes" => ["Run mix test and fix failing tests."]
    }

    prompt_request
    |> Ecto.Changeset.change(%{
      validation_feedback: Jason.encode!(feedback),
      validation_iterations: 2
    })
    |> Repo.update!()

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    html = render(view)
    assert html =~ "Validation Feedback"
    assert html =~ "Quality score: 72/100"
    assert html =~ "Minimum: 80/100"
    assert html =~ "Tests"
    assert html =~ "Run mix test and fix failing tests."
  end

  test "shows prompt request diff and accepts suggestions", %{conn: conn} do
    {user, organization, project} = setup_project()
    generated_at = DateTime.utc_now() |> DateTime.add(-3720, :second) |> DateTime.truncate(:second)

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Review diff",
          prompt: "User prompt content",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 800,
          generated_at: generated_at,
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt message"}]}
        },
        project: project,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert has_element?(view, "#prompt-request-diff")
    assert render(view) =~ "Attestation: Verified"
    assert render(view) =~ "Generated:"
    assert render(view) =~ "Submitted:"
    assert render(view) =~ "Lag: #{format_generation_lag(prompt_request)}"
    assert render(view) =~ "Review: Pending"
    assert render(view) =~ "Trust score:"
    assert render(view) =~ "Confidence:"
    assert render(view) =~ "Original Prompt"
    assert render(view) =~ "User prompt content"

    view |> element("#prompt-request-accept") |> render_click()

    assert render(view) =~ "Review: Accepted"
    assert has_element?(view, "#prompt-request-session-link")

    view |> element("#prompt-request-curate") |> render_click()

    assert render(view) =~ "Curated"

    suggestion_form =
      form(view, "#prompt-suggestion-form",
        prompt_suggestion: %{suggestion: "Make the prompt more specific"}
      )

    render_submit(suggestion_form)

    assert render(view) =~ "Make the prompt more specific"
  end

  test "shows prompt lineage and execution environment", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, parent} =
      PromptRequests.create_prompt_request(
        %{
          title: "Parent prompt",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, child} =
      PromptRequests.create_prompt_request(
        %{
          title: "Child prompt",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]},
          parent_prompt_request_id: parent.id,
          execution_environment: %{"runtime" => "phoenix", "os" => "linux"},
          execution_duration_ms: 4200
        },
        project: project,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{child.id}"
      )

    assert render(view) =~ "Prompt Lineage"
    assert render(view) =~ "Parent prompt"
    assert render(view) =~ "Execution Environment"
    assert render(view) =~ "\"runtime\": \"phoenix\""
  end

  test "shows validation runs for a prompt request", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Review validation",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 900,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, run} = ValidationEnvironments.create_run(prompt_request, %{status: :passed})

    run
    |> ValidationRun.changeset(%{
      metrics: %{"duration_ms" => 1200},
      resource_usage: %{"cpu_seconds" => 3.2, "memory_mb" => 256},
      coverage_delta: 0.01,
      check_results: %{"checks" => [%{"id" => "test"}]}
    })
    |> Repo.update!()

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert has_element?(view, "#prompt-request-run-validation")
    assert render(view) =~ "Validation Runs"
    assert render(view) =~ "Passed"
    assert render(view) =~ "Coverage delta"
  end

  test "allocates task budget from the prompt request page", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget request",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 750,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 200, reserved: 0})

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert render(view) =~ "Task budget"
    assert render(view) =~ "Available: 200 tokens"

    budget_form = form(view, "#task-budget-form", task_budget: %{amount: "60"})

    render_submit(budget_form)

    assert render(view) =~ "Allocated to this task"
    assert render(view) =~ ">60<"
  end

  test "caps task budget input based on pool availability", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget caps",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, pool} = AITokens.create_token_pool(project, %{balance: 200, reserved: 80})

    Repo.insert!(%TaskBudget{
      token_pool_id: pool.id,
      prompt_request_id: prompt_request.id,
      amount: 20
    })

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    html = render(view)
    assert html =~ "Available: 120 tokens"
    assert html =~ "max=\"140\""
  end

  test "rejects task budget above available tokens", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget guard",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 40, reserved: 0})

    conn = login_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    budget_form = form(view, "#task-budget-form", task_budget: %{amount: "60"})

    render_submit(budget_form)

    assert render(view) =~ "exceeds available tokens"
  end

  test "shows task budget note for non-admin members", %{conn: conn} do
    {admin, organization, project} = setup_project()

    {:ok, member} = Accounts.get_or_create_user_by_email("prompt-live-member@example.com")

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        organization_id: organization.id,
        user_id: member.id,
        role: "user"
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget note",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 400,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: admin
      )

    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 120, reserved: 0})

    conn = login_user(conn, member)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests/#{prompt_request.id}"
      )

    assert render(view) =~ "Only project admins can allocate task budgets."
    refute has_element?(view, "#task-budget-form")
  end

  test "flags invalid attestation on the prompt request list", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Tampered attestation",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 1100,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    prompt_request
    |> Ecto.Changeset.change(%{token_count: prompt_request.token_count + 1})
    |> Repo.update!()

    conn = login_user(conn, user)

    {:ok, list_view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests")

    assert render(list_view) =~ "Attestation: Invalid"
  end

  test "renders human-origin prompt requests without model metadata", %{conn: conn} do
    {user, organization, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Human review",
          prompt: "Summarize the work",
          result: "Manual result",
          origin: :human,
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Manual"}]}
        },
        project: project,
        user: user
      )

    conn = login_user(conn, user)

    {:ok, list_view, _html} =
      live(conn, ~p"/projects/#{organization.account.handle}/#{project.handle}/prompt-requests")

    assert render(list_view) =~ "Human"
    assert render(list_view) =~ "Model: n/a"
    assert render(list_view) =~ "Version: n/a"
    assert render(list_view) =~ "Tokens: n/a"
    assert render(list_view) =~ "Generated: n/a"
    assert render(list_view) =~ "Lag: n/a"
    assert render(list_view) =~ "Attestation: Verified"
    assert has_element?(list_view, "#prompt-request-#{prompt_request.id}")
  end

  defp format_generation_lag(prompt_request) do
    diff_seconds = DateTime.diff(prompt_request.inserted_at, prompt_request.generated_at, :second)

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
end
