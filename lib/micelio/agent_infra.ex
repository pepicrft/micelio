defmodule Micelio.AgentInfra do
  @moduledoc """
  API for shaping agent VM provisioning plans.
  """

  alias Micelio.AgentInfra.ProvisioningPlan
  alias Micelio.AgentInfra.ProvisioningRequest
  alias Micelio.AgentInfra.ProviderRegistry
  alias Micelio.AgentInfra.CloudPlatforms

  @doc """
  Builds a provisioning plan from attributes.
  """
  def build_plan(attrs) do
    %ProvisioningPlan{}
    |> ProvisioningPlan.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Builds a provider-ready request from attributes.
  """
  def build_request(attrs) do
    with {:ok, plan} <- build_plan(attrs) do
      {:ok, ProvisioningRequest.from_plan(plan)}
    end
  end

  @doc """
  Returns a changeset for inspecting or editing a plan.
  """
  def change_plan(%ProvisioningPlan{} = plan, attrs \\ %{}) do
    ProvisioningPlan.changeset(plan, attrs)
  end

  @doc """
  Returns evaluated cloud platforms for provisioning agent VMs.
  """
  def cloud_platforms do
    CloudPlatforms.all()
  end

  @doc """
  Returns a single platform evaluation by id.
  """
  def cloud_platform(id) do
    CloudPlatforms.find(id)
  end

  @doc """
  Resolves a provisioning provider module by id.
  """
  def provider_module(provider_id, providers \\ ProviderRegistry.providers()) do
    ProviderRegistry.resolve(provider_id, providers)
  end
end
