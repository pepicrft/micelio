defmodule Micelio.Accounts.Organization do
  use Micelio.Schema

  import Ecto.Changeset

  alias Micelio.LLM

  schema "organizations" do
    field :name, :string
    field :llm_models, {:array, :string}
    field :llm_default_model, :string
    field :member_count, :integer, virtual: true

    has_one :account, Micelio.Accounts.Account
    has_many :memberships, Micelio.Accounts.OrganizationMembership
    has_many :users, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new organization.
  """
  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :llm_models, :llm_default_model])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> normalize_llm_models()
    |> normalize_llm_default_model()
    |> validate_llm_models()
    |> validate_llm_default_model()
  end

  @doc """
  Changeset for updating organization settings.
  """
  def settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:llm_models, :llm_default_model])
    |> normalize_llm_models()
    |> normalize_llm_default_model()
    |> validate_llm_models()
    |> validate_llm_default_model()
  end

  defp validate_llm_models(changeset) do
    available = LLM.project_models()

    case get_field(changeset, :llm_models) do
      models when is_list(models) and models != [] and available != [] ->
        invalid = models -- available

        if invalid == [] do
          changeset
        else
          add_error(
            changeset,
            :llm_models,
            "contains unsupported models: #{Enum.join(invalid, ", ")}"
          )
        end

      _ ->
        changeset
    end
  end

  defp normalize_llm_models(changeset) do
    update_change(changeset, :llm_models, fn
      models when is_list(models) -> Enum.reject(models, &(&1 in [nil, ""]))
      models -> models
    end)
  end

  defp normalize_llm_default_model(changeset) do
    update_change(changeset, :llm_default_model, fn
      "" -> nil
      value -> value
    end)
  end

  defp validate_llm_default_model(changeset) do
    case get_field(changeset, :llm_default_model) do
      default when is_binary(default) and default != "" ->
        models =
          case get_field(changeset, :llm_models) do
            models when is_list(models) and models != [] -> models
            _ -> LLM.project_models()
          end

        if models == [] or default in models do
          changeset
        else
          add_error(changeset, :llm_default_model, "must be one of #{Enum.join(models, ", ")}")
        end

      _ ->
        changeset
    end
  end
end
