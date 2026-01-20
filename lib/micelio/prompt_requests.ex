defmodule Micelio.PromptRequests do
  @moduledoc """
  Context for prompt request contributions.
  """

  import Ecto.Query, warn: false

  alias Micelio.PromptRequests.{PromptRequest, PromptSuggestion}
  alias Micelio.ValidationEnvironments
  alias Micelio.Repo
  alias MicelioWeb.Endpoint

  def list_prompt_requests_for_project(project) do
    PromptRequest
    |> where([prompt_request], prompt_request.project_id == ^project.id)
    |> order_by([prompt_request], desc: prompt_request.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def count_prompt_requests_for_project(project) do
    PromptRequest
    |> where([prompt_request], prompt_request.project_id == ^project.id)
    |> select([prompt_request], count(prompt_request.id))
    |> Repo.one()
  end

  def get_prompt_request_for_project(project, id) do
    PromptRequest
    |> where([prompt_request],
      prompt_request.project_id == ^project.id and prompt_request.id == ^id
    )
    |> preload([:user, suggestions: :user])
    |> Repo.one()
  end

  def change_prompt_request(%PromptRequest{} = prompt_request, attrs \ %{}) do
    PromptRequest.changeset(prompt_request, attrs)
  end

  def create_prompt_request(attrs, opts) do
    project = Keyword.fetch!(opts, :project)
    user = Keyword.fetch!(opts, :user)

    %PromptRequest{}
    |> PromptRequest.changeset(attrs)
    |> Ecto.Changeset.put_change(:project_id, project.id)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> put_attestation()
    |> Repo.insert()
  end

  def list_prompt_suggestions(%PromptRequest{} = prompt_request) do
    PromptSuggestion
    |> where([prompt_suggestion], prompt_suggestion.prompt_request_id == ^prompt_request.id)
    |> order_by([prompt_suggestion], asc: prompt_suggestion.inserted_at)
    |> preload(:user)
    |> Repo.all()
  end

  def change_prompt_suggestion(%PromptSuggestion{} = prompt_suggestion, attrs \ %{}) do
    PromptSuggestion.changeset(prompt_suggestion, attrs)
  end

  def create_prompt_suggestion(%PromptRequest{} = prompt_request, attrs, opts) do
    user = Keyword.fetch!(opts, :user)

    %PromptSuggestion{}
    |> PromptSuggestion.changeset(attrs)
    |> Ecto.Changeset.put_change(:prompt_request_id, prompt_request.id)
    |> Ecto.Changeset.put_change(:user_id, user.id)
    |> Repo.insert()
  end

  def list_validation_runs(%PromptRequest{} = prompt_request) do
    ValidationEnvironments.list_runs_for_prompt_request(prompt_request)
  end

  def run_validation(%PromptRequest{} = prompt_request, opts \\ []) do
    config_opts = Application.get_env(:micelio, :validation_environments, [])
    ValidationEnvironments.run_for_prompt_request(prompt_request, Keyword.merge(config_opts, opts))
  end

  def run_validation_async(%PromptRequest{} = prompt_request, notify_pid, opts \\ []) do
    Task.Supervisor.start_child(Micelio.ValidationEnvironments.Supervisor, fn ->
      run_validation(prompt_request, Keyword.put(opts, :notify_pid, notify_pid))
    end)
  end

  def attestation_status(%PromptRequest{} = prompt_request) do
    case prompt_request.attestation do
      %{"signature" => signature} when is_binary(signature) ->
        if signature == sign_attestation(PromptRequest.attestation_payload(prompt_request)) do
          :verified
        else
          :invalid
        end

      _ ->
        :missing
    end
  end

  defp put_attestation(%Ecto.Changeset{valid?: true} = changeset) do
    payload = PromptRequest.attestation_payload(Ecto.Changeset.apply_changes(changeset))

    attestation = %{
      "signature" => sign_attestation(payload),
      "payload" => payload,
      "signed_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    Ecto.Changeset.put_change(changeset, :attestation, attestation)
  end

  defp put_attestation(changeset), do: changeset

  defp sign_attestation(payload) do
    secret = Endpoint.config(:secret_key_base) || raise "secret_key_base is required"
    data = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, data) |> Base.encode16(case: :lower)
  end
end
