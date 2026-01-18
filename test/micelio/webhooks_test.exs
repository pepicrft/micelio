defmodule Micelio.WebhooksTest do
  use Micelio.DataCase, async: true

  import Mimic

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Webhooks

  setup :verify_on_exit!
  setup :set_mimic_global

  setup_all do
    Mimic.copy(Req)
    Mimic.copy(Task.Supervisor)
    :ok
  end

  describe "deliver_project_event/3" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Acme",
          handle: "acme"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "repo",
          name: "Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, webhook} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/push",
          events: ["push"],
          secret: "super-secret"
        })

      {:ok, project: project, webhook: webhook}
    end

    test "posts payload with signature", %{project: project, webhook: webhook} do
      payload = %{"session_id" => "session-1"}

      expect(Req, :request, fn opts ->
        assert opts[:method] == :post
        assert opts[:url] == webhook.url

        headers = normalize_headers(opts[:headers])
        assert headers["content-type"] == "application/json"
        assert headers["x-micelio-event"] == "push"
        assert headers["x-micelio-hook-id"] == webhook.id

        body = opts[:body]
        decoded = Jason.decode!(body)

        assert decoded["event"] == "push"
        assert decoded["project"]["id"] == project.id
        assert decoded["payload"] == payload

        assert headers["x-micelio-signature"] == "sha256=" <> sign("super-secret", body)

        {:ok, %{status: 200, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 200}]} =
               Webhooks.deliver_project_event(project, "push", payload)
    end

    test "delivers only active webhooks with matching events", %{project: project, webhook: webhook} do
      {:ok, _inactive} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/disabled",
          events: ["push"],
          active: false
        })

      {:ok, _different_event} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/session",
          events: ["session.landed"]
        })

      payload = %{"session_id" => "session-2"}

      expect(Req, :request, fn opts ->
        headers = normalize_headers(opts[:headers])
        assert headers["x-micelio-hook-id"] == webhook.id
        {:ok, %{status: 204, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 204}]} =
               Webhooks.deliver_project_event(project, "push", payload)
    end
  end

  describe "dispatch_project_event/4" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Dispatch Co",
          handle: "dispatch-co"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "dispatch-repo",
          name: "Dispatch Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, project: project}
    end

    test "starts async delivery for known events", %{project: project} do
      Mimic.stub(Task.Supervisor, :start_child, fn _name, _fun ->
        send(self(), :task_started)
        {:ok, self()}
      end)

      assert :ok == Webhooks.dispatch_project_event(project, "push", %{"ok" => true})
      assert_receive :task_started
    end

    test "rejects unknown events without starting a task", %{project: project} do
      Mimic.stub(Task.Supervisor, :start_child, fn _name, _fun ->
        send(self(), :task_started)
        {:ok, self()}
      end)

      assert {:error, :unknown_event} ==
               Webhooks.dispatch_project_event(project, "unknown.event", %{"ok" => true})

      refute_receive :task_started
    end
  end

  describe "deliver_project_event/3 without secret" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "No Secret Org",
          handle: "no-secret-org"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "no-secret-repo",
          name: "No Secret Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, webhook} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/no-secret",
          events: ["push"],
          secret: ""
        })

      {:ok, project: project, webhook: webhook}
    end

    test "omits signature header", %{project: project, webhook: webhook} do
      payload = %{"session_id" => "session-3"}

      expect(Req, :request, fn opts ->
        assert opts[:url] == webhook.url
        headers = normalize_headers(opts[:headers])
        refute Map.has_key?(headers, "x-micelio-signature")
        {:ok, %{status: 202, body: ""}}
      end)

      assert {:ok, [%{webhook: ^webhook, status: :ok, response_status: 202}]} =
               Webhooks.deliver_project_event(project, "push", payload)
    end
  end

  describe "dispatch_session_landed/3" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Landing Org",
          handle: "landing-org"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "landing-repo",
          name: "Landing Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, user} = Accounts.get_or_create_user_by_email("session-landed@example.com")

      {:ok, session} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Ship landing",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _hook} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/session",
          events: ["session.landed"]
        })

      {:ok, _hook} =
        Webhooks.create_webhook(%{
          project_id: project.id,
          url: "https://hooks.example.com/push",
          events: ["push"]
        })

      {:ok, project: project, session: session}
    end

    test "dispatches session.landed and push events", %{project: project, session: session} do
      Mimic.stub(Task.Supervisor, :start_child, fn _name, fun ->
        send(self(), :task_started)
        fun.()
        {:ok, self()}
      end)

      Mimic.expect(Req, :request, 2, fn opts ->
        headers = normalize_headers(opts[:headers])
        send(self(), {:webhook_event, headers["x-micelio-event"]})
        {:ok, %{status: 200, body: ""}}
      end)

      assert :ok == Webhooks.dispatch_session_landed(project, session, 42)

      for _ <- 1..2 do
        assert_receive :task_started
      end

      events =
        for _ <- 1..2 do
          assert_receive {:webhook_event, event}
          event
        end

      assert Enum.sort(events) == ["push", "session.landed"]
    end
  end

  describe "create_webhook/1" do
    test "rejects unsupported events" do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Beta",
          handle: "beta"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "repo",
          name: "Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      assert {:error, changeset} =
               Webhooks.create_webhook(%{
                 project_id: project.id,
                 url: "https://hooks.example.com/invalid",
                 events: ["unknown.event"]
               })

      assert "contains unsupported events" in errors_on(changeset).events
    end

    test "rejects invalid urls" do
      {:ok, organization} =
        Accounts.create_organization(%{
          name: "Invalid Url Org",
          handle: "invalid-url-org"
        })

      {:ok, project} =
        Projects.create_project(%{
          handle: "invalid-url-repo",
          name: "Invalid Url Repo",
          description: "Test",
          organization_id: organization.id,
          visibility: "public"
        })

      assert {:error, changeset} =
               Webhooks.create_webhook(%{
                 project_id: project.id,
                 url: "ftp://hooks.example.com",
                 events: ["push"]
               })

      assert "must be a valid http(s) URL" in errors_on(changeset).url
    end
  end

  defp normalize_headers(headers) do
    Enum.reduce(headers, %{}, fn {key, value}, acc ->
      Map.put(acc, String.downcase(to_string(key)), value)
    end)
  end

  defp sign(secret, body) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end
end
