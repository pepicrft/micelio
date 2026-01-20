defmodule Micelio.LLM do
  @moduledoc false

  @doc "Returns configured LLM models that can be selected per project."
  def project_models do
    Application.get_env(:micelio, :project_llm_models, [])
  end

  @doc "Returns configured LLM models for a specific organization."
  def project_models_for_organization(%{llm_models: models}) when is_list(models) do
    available = project_models()

    models =
      if available == [] do
        models
      else
        Enum.filter(models, &(&1 in available))
      end

    if models == [], do: available, else: models
  end

  def project_models_for_organization(_organization), do: project_models()

  @doc "Returns the default LLM model for new projects."
  def project_default_model do
    Application.get_env(:micelio, :project_llm_default) || List.first(project_models())
  end

  @doc "Returns the default LLM model for a specific organization."
  def project_default_model_for_organization(%{llm_default_model: model} = organization)
      when is_binary(model) and model != "" do
    model
  end

  def project_default_model_for_organization(organization) do
    project_models_for_organization(organization)
    |> List.first()
    |> case do
      nil -> project_default_model()
      model -> model
    end
  end

  @doc "Returns select options for project LLM models."
  def project_model_options do
    Enum.map(project_models(), &{&1, &1})
  end

  @doc "Returns select options for project LLM models by organization."
  def project_model_options_for_organization(organization) do
    organization
    |> project_models_for_organization()
    |> Enum.map(&{&1, &1})
  end
end
