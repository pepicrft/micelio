defmodule Micelio.ReputationTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.PromptRequests
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Projects
  alias Micelio.Reputation
  alias Micelio.Repo
  alias Micelio.Sessions
  alias Micelio.ValidationEnvironments
  alias Micelio.ValidationEnvironments.ValidationRun

  import Ecto.Query, warn: false

  defp setup_project(email) do
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "rep-org-#{System.unique_integer([:positive])}",
        name: "Rep Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "rep-project-#{System.unique_integer([:positive])}",
        name: "Rep Project",
        organization_id: organization.id
      })

    {user, project}
  end

  defp create_prompt_request(user, project, attrs \\ %{}) do
    PromptRequests.create_prompt_request(
      Map.merge(
        %{
          title: "Fix validation",
          prompt: "Fix failing tests",
          result: "Diff",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_assisted,
          token_count: 800,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Fix"}]}
        },
        attrs
      ),
      project: project,
      user: user
    )
  end

  test "builds trust scores with per-type tracks" do
    {user, project} = setup_project("rep-user@example.com")

    {:ok, prompt_request} = create_prompt_request(user, project, %{title: "Docs update"})
    {:ok, _reviewed} = PromptRequests.review_prompt_request(prompt_request, user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(prompt_request, %{status: :passed})

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "rep-session",
        goal: "Fix login bug",
        project_id: project.id,
        user_id: user.id
      })

    {:ok, _} = Sessions.land_session(session)

    score = Reputation.trust_score_for_user(user)

    assert score.overall >= 0
    assert Map.has_key?(score.by_type, :docs)
    assert Map.has_key?(score.by_type, :tests)
    assert Map.has_key?(score.by_type, :features)
    assert Map.has_key?(score.by_type, :fixes)
  end

  test "penalizes rejected contributions that passed validation" do
    {good_user, project} = setup_project("rep-good@example.com")

    {:ok, good_prompt} = create_prompt_request(good_user, project)
    {:ok, _reviewed} = PromptRequests.review_prompt_request(good_prompt, good_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(good_prompt, %{status: :passed})

    good_score = Reputation.trust_score_for_user(good_user).overall

    {bad_user, bad_project} = setup_project("rep-bad@example.com")

    {:ok, bad_prompt} = create_prompt_request(bad_user, bad_project)
    {:ok, _reviewed} = PromptRequests.review_prompt_request(bad_prompt, bad_user, :rejected)
    {:ok, _run} = ValidationEnvironments.create_run(bad_prompt, %{status: :passed})

    bad_score = Reputation.trust_score_for_user(bad_user).overall

    assert bad_score <= good_score
  end

  test "reduces trust score when review iterations increase" do
    {clean_user, project} = setup_project("rep-clean@example.com")

    {:ok, clean_prompt} = create_prompt_request(clean_user, project)
    {:ok, _reviewed} = PromptRequests.review_prompt_request(clean_prompt, clean_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(clean_prompt, %{status: :passed})

    clean_score = Reputation.trust_score_for_user(clean_user).overall

    {iter_user, iter_project} = setup_project("rep-iter@example.com")

    {:ok, iter_prompt} = create_prompt_request(iter_user, iter_project)

    for index <- 1..5 do
      {:ok, _suggestion} =
        PromptRequests.create_prompt_suggestion(
          iter_prompt,
          %{suggestion: "Iteration #{index}"},
          user: iter_user
        )
    end

    {:ok, _reviewed} = PromptRequests.review_prompt_request(iter_prompt, iter_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(iter_prompt, %{status: :passed})

    iter_score = Reputation.trust_score_for_user(iter_user).overall

    assert iter_score < clean_score
  end

  test "decays trust score for older contributions" do
    {recent_user, recent_project} = setup_project("rep-recent@example.com")

    {:ok, recent_prompt} = create_prompt_request(recent_user, recent_project)
    {:ok, _reviewed} = PromptRequests.review_prompt_request(recent_prompt, recent_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(recent_prompt, %{status: :passed})

    recent_score = Reputation.trust_score_for_user(recent_user).overall

    {old_user, old_project} = setup_project("rep-old@example.com")

    {:ok, old_prompt} = create_prompt_request(old_user, old_project)
    {:ok, _reviewed} = PromptRequests.review_prompt_request(old_prompt, old_user, :accepted)
    {:ok, _run} = ValidationEnvironments.create_run(old_prompt, %{status: :passed})

    old_time =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.add(-720 * 24 * 60 * 60, :second)

    Repo.update_all(
      from(prompt_request in PromptRequest, where: prompt_request.id == ^old_prompt.id),
      set: [inserted_at: old_time, updated_at: old_time]
    )

    Repo.update_all(
      from(run in ValidationRun, where: run.prompt_request_id == ^old_prompt.id),
      set: [inserted_at: old_time, updated_at: old_time, completed_at: old_time]
    )

    old_score = Reputation.trust_score_for_user(old_user).overall

    assert recent_score > old_score
  end
end
