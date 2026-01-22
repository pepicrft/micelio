defmodule MicelioWeb.Api.PromptRequestControllerTest do
  use MicelioWeb.ConnCase, async: false

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias Micelio.Projects
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repo
  alias Micelio.Sessions

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("prompt-api@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{handle: "prompt-org", name: "Prompt Org"})

    {:ok, project} =
      Projects.create_project(%{
        handle: "prompt-project",
        name: "Prompt Project",
        organization_id: organization.id
      })

    token = create_access_token(user)
    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 5_000, reserved: 0})

    %{user: user, token: token, project: project, organization: organization}
  end

  test "creates prompt request and converts to session when validation passes", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    Process.put(:validation_test_pid, self())
    previous_flow = Application.get_env(:micelio, :prompt_request_flow)

    Application.put_env(:micelio, :prompt_request_flow,
      validation_enabled: true,
      validation_async: true,
      task_budget_amount: "1500",
      validation_opts: [
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
      ]
    )

    on_exit(fn ->
      if previous_flow do
        Application.put_env(:micelio, :prompt_request_flow, previous_flow)
      else
        Application.delete_env(:micelio, :prompt_request_flow)
      end
    end)

    params = %{
      prompt_request: %{
        title: "API prompt request",
        prompt: "Generate the change",
        result: "Change output",
        model: "gpt-4.1",
        model_version: "2025-02-01",
        origin: "ai_generated",
        token_count: 800,
        generated_at: "2025-02-10T12:00:00Z",
        system_prompt: "System",
        conversation: %{messages: [%{role: "user", content: "Do it"}]}
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/prompt-requests",
        params
      )

    body = json_response(conn, 201)
    data = body["data"]

    assert data["review_status"] == "accepted"
    assert data["validation_feedback"] == nil
    assert data["validation_iterations"] == 1
    assert is_binary(data["session_id"])

    prompt_request = Repo.get!(PromptRequest, data["id"])
    session = Sessions.get_session(prompt_request.session_id)

    assert session.session_id == "prompt-request-#{prompt_request.id}"
  end

  test "returns validation feedback when quality gate fails", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    previous_flow = Application.get_env(:micelio, :prompt_request_flow)

    Application.put_env(:micelio, :prompt_request_flow,
      validation_enabled: true,
      validation_async: true,
      task_budget_amount: "1500",
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

    params = %{
      prompt_request: %{
        title: "API prompt request failure",
        prompt: "Generate the change",
        result: "Change output",
        model: "gpt-4.1",
        model_version: "2025-02-01",
        origin: "ai_generated",
        token_count: 800,
        generated_at: "2025-02-10T12:00:00Z",
        system_prompt: "System",
        conversation: %{messages: [%{role: "user", content: "Do it"}]}
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/prompt-requests",
        params
      )

    body = json_response(conn, 422)
    assert body["error"] =~ "Validation failed"
    assert is_map(body["feedback"])
    assert Enum.any?(body["feedback"]["failures"], &(&1["check_id"] == "test"))
    assert body["data"]["review_status"] == "rejected"
  end

  test "returns validation feedback when quality score is below minimum", %{
    conn: conn,
    token: token,
    project: project,
    organization: organization
  } do
    previous_flow = Application.get_env(:micelio, :prompt_request_flow)

    Application.put_env(:micelio, :prompt_request_flow,
      validation_enabled: true,
      validation_async: true,
      task_budget_amount: "1500",
      validation_opts: [
        min_quality_score: 101,
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
      ]
    )

    on_exit(fn ->
      if previous_flow do
        Application.put_env(:micelio, :prompt_request_flow, previous_flow)
      else
        Application.delete_env(:micelio, :prompt_request_flow)
      end
    end)

    params = %{
      prompt_request: %{
        title: "API prompt request low quality score",
        prompt: "Generate the change",
        result: "Change output",
        model: "gpt-4.1",
        model_version: "2025-02-01",
        origin: "ai_generated",
        token_count: 800,
        generated_at: "2025-02-10T12:00:00Z",
        system_prompt: "System",
        conversation: %{messages: [%{role: "user", content: "Do it"}]}
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(
        ~p"/api/projects/#{organization.account.handle}/#{project.handle}/prompt-requests",
        params
      )

    body = json_response(conn, 422)
    assert body["error"] =~ "quality score"
    assert body["data"]["review_status"] == "rejected"
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "mic"})
    client = Clients.get_client(device_client.client_id)

    params = %{
      client: client,
      scope: "",
      sub: to_string(user.id),
      resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
    }

    {:ok, token} = AccessTokens.create(params, refresh_token: true)
    Map.get(token, :value) || Map.get(token, :access_token)
  end
end
