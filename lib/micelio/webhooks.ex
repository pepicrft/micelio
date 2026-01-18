defmodule Micelio.Webhooks do
  @moduledoc """
  Manage repository webhooks and deliver repository events.
  """

  import Ecto.Query

  alias Micelio.Projects.Project
  alias Micelio.Repo
  alias Micelio.Sessions.Session
  alias Micelio.Webhooks.Webhook

  require Logger

  @supervisor Micelio.Webhooks.Supervisor
  @default_timeout 5_000

  @doc """
  Lists all webhooks for a project.
  """
  def list_webhooks_for_project(project_id) do
    Webhook
    |> where([w], w.project_id == ^project_id)
    |> Repo.all()
  end

  @doc """
  Lists active webhooks for a project.
  """
  def list_active_webhooks_for_project(project_id) do
    Webhook
    |> where([w], w.project_id == ^project_id and w.active == true)
    |> Repo.all()
  end

  @doc """
  Fetches a webhook by id scoped to a project.
  """
  def get_webhook_for_project(project_id, webhook_id) do
    Repo.get_by(Webhook, id: webhook_id, project_id: project_id)
  end

  @doc """
  Creates a webhook.
  """
  def create_webhook(attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a webhook.
  """
  def update_webhook(%Webhook{} = webhook, attrs) do
    webhook
    |> Webhook.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a webhook.
  """
  def delete_webhook(%Webhook{} = webhook), do: Repo.delete(webhook)

  @doc """
  Returns a webhook changeset.
  """
  def change_webhook(%Webhook{} = webhook, attrs \\ %{}) do
    Webhook.changeset(webhook, attrs)
  end

  @doc """
  Dispatches a webhook event for a landed session.
  """
  def dispatch_session_landed(%Project{} = project, %Session{} = session, landing_position) do
    payload = session_payload(session, landing_position)

    dispatch_project_event(project, "session.landed", payload)
    dispatch_project_event(project, "push", payload)
    :ok
  end

  @doc """
  Dispatches a project event asynchronously.
  """
  def dispatch_project_event(%Project{} = project, event, payload, opts \\ [])
      when is_binary(event) and is_map(payload) do
    if event in Webhook.allowed_events() do
      case Task.Supervisor.start_child(@supervisor, fn ->
             deliver_project_event(project, event, payload, opts)
           end) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.warning("webhook dispatch failed: #{inspect(reason)}")
          :error
      end
    else
      {:error, :unknown_event}
    end
  end

  @doc """
  Delivers a project event to all matching webhooks.
  """
  def deliver_project_event(%Project{} = project, event, payload, opts \\ [])
      when is_binary(event) and is_map(payload) do
    if event in Webhook.allowed_events() do
      webhooks =
        project.id
        |> list_active_webhooks_for_project()
        |> Enum.filter(fn webhook -> event in webhook.events end)

      deliveries =
        Enum.map(webhooks, fn webhook ->
          deliver_webhook(project, webhook, event, payload, opts)
        end)

      {:ok, deliveries}
    else
      {:error, :unknown_event}
    end
  end

  defp deliver_webhook(%Project{} = project, %Webhook{} = webhook, event, payload, opts) do
    delivery_id = Ecto.UUID.generate()
    body = webhook_body(project, event, payload, delivery_id)
    headers = webhook_headers(webhook, event, delivery_id, body)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case Req.request(
           method: :post,
           url: webhook.url,
           headers: headers,
           body: body,
           receive_timeout: timeout,
           retry: false
         ) do
      {:ok, %{status: status}} when status >= 200 and status < 300 ->
        %{webhook: webhook, status: :ok, response_status: status}

      {:ok, %{status: status, body: response_body}} ->
        %{
          webhook: webhook,
          status: :error,
          response_status: status,
          response_body: response_body
        }

      {:error, reason} ->
        %{webhook: webhook, status: :error, reason: reason}
    end
  end

  defp webhook_body(%Project{} = project, event, payload, delivery_id) do
    Jason.encode!(%{
      "id" => delivery_id,
      "event" => event,
      "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "project" => %{
        "id" => project.id,
        "handle" => project.handle,
        "name" => project.name,
        "organization_id" => project.organization_id
      },
      "payload" => payload
    })
  end

  defp webhook_headers(%Webhook{} = webhook, event, delivery_id, body) do
    base = [
      {"content-type", "application/json"},
      {"user-agent", "Micelio-Webhooks/1.0"},
      {"x-micelio-event", event},
      {"x-micelio-delivery", delivery_id},
      {"x-micelio-hook-id", webhook.id}
    ]

    case webhook.secret do
      secret when is_binary(secret) and secret != "" ->
        signature = sign_body(secret, body)
        base ++ [{"x-micelio-signature", "sha256=" <> signature}]

      _ ->
        base
    end
  end

  defp sign_body(secret, body) do
    :crypto.mac(:hmac, :sha256, secret, body)
    |> Base.encode16(case: :lower)
  end

  defp session_payload(%Session{} = session, landing_position) do
    %{
      "session_id" => session.session_id,
      "status" => session.status,
      "user_id" => session.user_id,
      "project_id" => session.project_id,
      "landing_position" => landing_position,
      "landed_at" => format_datetime(session.landed_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
end
