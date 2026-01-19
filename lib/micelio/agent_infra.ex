defmodule Micelio.AgentInfra do
  @moduledoc """
  API for shaping agent VM provisioning plans.
  """

  alias Micelio.AgentInfra.ProvisioningPlan

  @doc """
  Builds a provisioning plan from attributes.
  """
  def build_plan(attrs) do
    %ProvisioningPlan{}
    |> ProvisioningPlan.changeset(attrs)
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc """
  Returns a changeset for inspecting or editing a plan.
  """
  def change_plan(%ProvisioningPlan{} = plan, attrs \\ %{}) do
    ProvisioningPlan.changeset(plan, attrs)
  end
end
