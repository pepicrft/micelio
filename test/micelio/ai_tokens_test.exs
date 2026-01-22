defmodule Micelio.AITokensTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.AITokens.TokenContribution
  alias Micelio.Projects
  alias Micelio.PromptRequests
  alias Micelio.Repo

  setup do
    {:ok, organization} =
      Accounts.create_organization(%{handle: "ai-tokens", name: "AI Tokens"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "token-pool",
        name: "Token Pool",
        organization_id: organization.id
      })

    {:ok, organization: organization, project: project}
  end

  test "create_token_pool/2 persists defaults", %{project: project} do
    assert {:ok, pool} = AITokens.create_token_pool(project)
    assert pool.project_id == project.id
    assert pool.balance == 0
    assert pool.reserved == 0
  end

  test "get_or_create_token_pool/1 reuses existing pool", %{project: project} do
    assert {:ok, pool} = AITokens.get_or_create_token_pool(project)
    assert {:ok, same_pool} = AITokens.get_or_create_token_pool(project)
    assert pool.id == same_pool.id
  end

  test "update_token_pool/2 rejects reserved above balance", %{project: project} do
    assert {:ok, pool} = AITokens.create_token_pool(project)

    assert {:error, changeset} =
             AITokens.update_token_pool(pool, %{balance: 5, reserved: 10})

    assert "cannot exceed balance" in errors_on(changeset).reserved
  end

  test "project_usage_summary/1 aggregates usage metrics", %{project: project} do
    {:ok, user} = Accounts.get_or_create_user_by_email("usage@example.com")

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Usage prompt",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 120,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, _} = PromptRequests.review_prompt_request(prompt_request, user, :accepted)

    {:ok, rejected_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Usage reject",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 30,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, _} = PromptRequests.review_prompt_request(rejected_request, user, :rejected)

    {:ok, _} =
      PromptRequests.create_prompt_request(
        %{
          title: "Human prompt",
          prompt: "Prompt",
          result: "Result",
          origin: :human,
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    summary = AITokens.project_usage_summary(project)

    assert summary.tokens_spent == 150
    assert summary.accepted_prompt_requests == 1
    assert summary.total_prompt_requests == 3
  end

  test "contribute_tokens/3 records contribution and updates balance", %{project: project} do
    {:ok, user} = Accounts.get_or_create_user_by_email("donor@example.com")

    assert {:ok, contribution, pool} =
             AITokens.contribute_tokens(project, user, %{"amount" => "25"})

    assert contribution.amount == 25
    assert contribution.project_id == project.id
    assert contribution.user_id == user.id
    assert pool.balance == 25
    assert Repo.aggregate(TokenContribution, :count, :id) == 1
  end

  test "contribute_tokens/3 rejects non-positive amounts", %{project: project} do
    {:ok, user} = Accounts.get_or_create_user_by_email("donor-two@example.com")

    assert {:error, changeset} =
             AITokens.contribute_tokens(project, user, %{"amount" => "0"})

    assert "must be greater than 0" in errors_on(changeset).amount
  end

  test "upsert_task_budget/2 reserves tokens for a prompt request", %{project: project} do
    {:ok, user} = Accounts.get_or_create_user_by_email("budgeter@example.com")

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget task",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 200,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, pool} = AITokens.create_token_pool(project, %{balance: 120, reserved: 0})

    assert {:ok, budget, updated_pool} =
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "40"})

    assert budget.amount == 40
    assert updated_pool.id == pool.id
    assert updated_pool.reserved == 40

    assert {:ok, budget, updated_pool} =
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "70"})

    assert budget.amount == 70
    assert updated_pool.reserved == 70
  end

  test "upsert_task_budget/2 rejects allocations above available", %{project: project} do
    {:ok, user} = Accounts.get_or_create_user_by_email("budgeter-two@example.com")

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Budget overflow",
          prompt: "Prompt",
          result: "Result",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 200,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Prompt"}]}
        },
        project: project,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 50, reserved: 0})

    assert {:error, :insufficient_tokens} =
             AITokens.upsert_task_budget(prompt_request, %{"amount" => "70"})
  end
end
