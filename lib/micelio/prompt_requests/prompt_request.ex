defmodule Micelio.PromptRequests.PromptRequest do
  use Ecto.Schema

  import Ecto.Changeset

  alias Micelio.PromptRequests.PromptSuggestion

  @origin_values [:ai_generated, :ai_assisted, :human]
  @review_status_values [:pending, :accepted, :rejected]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompt_requests" do
    field :title, :string
    field :prompt, :string
    field :result, :string
    field :model, :string
    field :model_version, :string
    field :origin, Ecto.Enum, values: @origin_values, default: :ai_generated
    field :review_status, Ecto.Enum, values: @review_status_values, default: :pending
    field :validation_feedback, :string
    field :validation_iterations, :integer, default: 0
    field :token_count, :integer
    field :generated_at, :utc_datetime
    field :system_prompt, :string
    field :conversation, :map, default: %{}
    field :attestation, :map, default: %{}
    field :reviewed_at, :utc_datetime
    field :execution_environment, :map
    field :execution_duration_ms, :integer
    field :curated_at, :utc_datetime

    belongs_to :project, Micelio.Projects.Project
    belongs_to :user, Micelio.Accounts.User
    belongs_to :reviewed_by, Micelio.Accounts.User
    belongs_to :curated_by, Micelio.Accounts.User
    belongs_to :session, Micelio.Sessions.Session
    belongs_to :prompt_template, Micelio.PromptRequests.PromptTemplate
    belongs_to :parent_prompt_request, __MODULE__
    has_many :child_prompt_requests, __MODULE__, foreign_key: :parent_prompt_request_id
    has_many :suggestions, PromptSuggestion
    has_many :validation_runs, Micelio.ValidationEnvironments.ValidationRun
    has_one :task_budget, Micelio.AITokens.TaskBudget

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prompt_request, attrs) do
    prompt_request
    |> cast(attrs, [
      :title,
      :prompt,
      :result,
      :model,
      :model_version,
      :origin,
      :token_count,
      :generated_at,
      :system_prompt,
      :execution_environment,
      :execution_duration_ms,
      :parent_prompt_request_id,
      :prompt_template_id
    ])
    |> cast_generated_at(attrs)
    |> cast_conversation(attrs)
    |> cast_execution_environment(attrs)
    |> normalize_text_fields()
    |> validate_required([:title, :prompt, :result, :system_prompt, :conversation, :origin])
    |> validate_length(:title, max: 120)
    |> validate_length(:model, max: 120)
    |> validate_length(:model_version, max: 120)
    |> validate_number(:token_count, greater_than_or_equal_to: 0)
    |> validate_number(:execution_duration_ms, greater_than_or_equal_to: 0)
    |> validate_ai_requirements()
    |> validate_conversation()
    |> foreign_key_constraint(:parent_prompt_request_id)
    |> foreign_key_constraint(:prompt_template_id)
  end

  def review_changeset(prompt_request, attrs) do
    prompt_request
    |> cast(attrs, [:review_status, :reviewed_at, :reviewed_by_id])
    |> validate_required([:review_status])
  end

  def curation_changeset(prompt_request, attrs) do
    prompt_request
    |> cast(attrs, [:curated_at, :curated_by_id])
    |> validate_required([:curated_at, :curated_by_id])
    |> foreign_key_constraint(:curated_by_id)
  end

  defp cast_conversation(changeset, attrs) do
    case Map.get(attrs, :conversation) || Map.get(attrs, "conversation") do
      nil ->
        changeset

      "" ->
        put_change(changeset, :conversation, %{})

      value when is_map(value) ->
        put_change(changeset, :conversation, value)

      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_map(decoded) ->
            put_change(changeset, :conversation, decoded)

          _ ->
            add_error(changeset, :conversation, "must be valid JSON object")
        end

      _ ->
        add_error(changeset, :conversation, "must be valid JSON")
    end
  end

  defp cast_execution_environment(changeset, attrs) do
    case Map.get(attrs, :execution_environment) || Map.get(attrs, "execution_environment") do
      nil ->
        changeset

      "" ->
        put_change(changeset, :execution_environment, nil)

      value when is_map(value) ->
        put_change(changeset, :execution_environment, value)

      value when is_binary(value) ->
        case Jason.decode(value) do
          {:ok, decoded} when is_map(decoded) ->
            put_change(changeset, :execution_environment, decoded)

          _ ->
            add_error(changeset, :execution_environment, "must be valid JSON object")
        end

      _ ->
        add_error(changeset, :execution_environment, "must be valid JSON")
    end
  end

  defp normalize_text_fields(changeset) do
    changeset
    |> update_change(:title, &normalize_text/1)
    |> update_change(:prompt, &normalize_text/1)
    |> update_change(:result, &normalize_text/1)
    |> update_change(:model, &normalize_text/1)
    |> update_change(:model_version, &normalize_text/1)
    |> update_change(:system_prompt, &normalize_text/1)
  end

  defp normalize_text(nil), do: nil

  defp normalize_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_conversation(changeset) do
    validate_change(changeset, :conversation, fn :conversation, value ->
      if is_map(value) and map_size(value) > 0 do
        []
      else
        [conversation: "must include conversation history"]
      end
    end)
  end

  def origin_label(:ai_generated), do: "AI-generated"
  def origin_label(:ai_assisted), do: "AI-assisted"
  def origin_label(:human), do: "Human"
  def origin_label(nil), do: "Unknown"

  def attestation_payload(%__MODULE__{} = prompt_request) do
    %{
      "origin" => origin_value(prompt_request.origin),
      "model" => prompt_request.model,
      "model_version" => prompt_request.model_version,
      "token_count" => prompt_request.token_count,
      "generated_at" => format_datetime(prompt_request.generated_at),
      "user_id" => prompt_request.user_id,
      "project_id" => prompt_request.project_id
    }
  end

  defp origin_value(origin) when is_atom(origin), do: Atom.to_string(origin)
  defp origin_value(origin) when is_binary(origin), do: origin
  defp origin_value(_), do: nil

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp validate_ai_requirements(changeset) do
    case get_field(changeset, :origin) do
      :human ->
        changeset

      _ ->
        changeset
        |> validate_required([:model, :model_version, :token_count, :generated_at])
    end
  end

  defp cast_generated_at(changeset, attrs) do
    case Map.get(attrs, :generated_at) || Map.get(attrs, "generated_at") do
      nil ->
        changeset

      "" ->
        put_change(changeset, :generated_at, nil)

      %DateTime{} = datetime ->
        put_change(changeset, :generated_at, datetime)

      %NaiveDateTime{} = datetime ->
        put_change(changeset, :generated_at, DateTime.from_naive!(datetime, "Etc/UTC"))

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} ->
            put_change(changeset, :generated_at, datetime)

          {:error, _} ->
            case NaiveDateTime.from_iso8601(value) do
              {:ok, naive} ->
                put_change(changeset, :generated_at, DateTime.from_naive!(naive, "Etc/UTC"))

              {:error, _} ->
                add_error(changeset, :generated_at, "must be valid datetime")
            end
        end

      _ ->
        add_error(changeset, :generated_at, "must be valid datetime")
    end
  end
end
