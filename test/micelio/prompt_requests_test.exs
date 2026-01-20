defmodule Micelio.PromptRequestsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.PromptRequests
  alias Micelio.Projects

  defp setup_project do
    {:ok, user} = Accounts.get_or_create_user_by_email("prompt-requests@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "prompt-org",
        name: "Prompt Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "prompt-project",
        name: "Prompt Project",
        organization_id: organization.id
      })

    {user, project}
  end

  test "creates prompt request with agent context" do
    {user, project} = setup_project()

    attrs = %{
      title: "Add prompt request system",
      prompt: "Implement the prompt request flow",
      result: "Diff output",
      model: "gpt-4.1",
      model_version: "2025-02-01",
      origin: :ai_generated,
      token_count: 1420,
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      system_prompt: "System instructions",
      conversation: %{
        "messages" => [
          %{"role" => "user", "content" => "Implement a feature"}
        ]
      }
    }

    assert {:ok, prompt_request} =
             PromptRequests.create_prompt_request(attrs, project: project, user: user)

    assert prompt_request.project_id == project.id
    assert prompt_request.user_id == user.id
    assert prompt_request.conversation["messages"] != []
    assert PromptRequests.attestation_status(prompt_request) == :verified

    assert [listed] = PromptRequests.list_prompt_requests_for_project(project)
    assert listed.id == prompt_request.id
  end

  test "creates prompt improvement suggestions" do
    {user, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Improve prompt",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 620,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: project,
        user: user
      )

    assert {:ok, _suggestion} =
             PromptRequests.create_prompt_suggestion(
               prompt_request,
               %{suggestion: "Add constraints for edge cases"},
               user: user
             )

    assert [suggestion] = PromptRequests.list_prompt_suggestions(prompt_request)
    assert suggestion.suggestion =~ "edge cases"
  end

  test "runs validation for a prompt request and records runs" do
    Process.put(:validation_test_pid, self())
    {user, project} = setup_project()

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Validate contribution",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 2100,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: project,
        user: user
      )

    assert {:ok, run} =
             PromptRequests.run_validation(prompt_request,
               provider_module: Micelio.TestValidationProvider,
               executor: Micelio.TestValidationExecutor,
               plan_attrs: %{
                 provider: "aws",
                 image: "micelio/validation-runner:latest",
                 cpu_cores: 2,
                 memory_mb: 1024,
                 disk_gb: 10,
                 ttl_seconds: 1200,
                 network: "egress"
               }
             )

    assert run.status == :passed
    assert run.coverage_delta == 0.03
    assert run.metrics["duration_ms"] > 0
    assert run.resource_usage["cpu_seconds"] == 3.5
    assert run.resource_usage["memory_mb"] == 128
    assert_received {:validate_request, _request}
    assert_received {:provision, _request}
    assert_received {:terminate, %{id: "test-vm"}}

    [listed | _] = PromptRequests.list_validation_runs(prompt_request)
    assert listed.id == run.id
  end
end
