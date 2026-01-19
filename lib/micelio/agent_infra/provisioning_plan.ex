defmodule Micelio.AgentInfra.ProvisioningPlan do
  @moduledoc """
  Defines the provisioning plan for agent VMs, including volume mounts.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Micelio.AgentInfra.VolumeMount

  @primary_key false
  embedded_schema do
    field :provider, :string
    field :image, :string
    field :cpu_cores, :integer
    field :memory_mb, :integer
    field :disk_gb, :integer
    field :network, :string
    field :ttl_seconds, :integer
    embeds_many :volumes, VolumeMount, on_replace: :delete
  end

  @doc """
  Builds a changeset for a provisioning plan.
  """
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:provider, :image, :cpu_cores, :memory_mb, :disk_gb, :network, :ttl_seconds])
    |> cast_embed(:volumes, required: false)
    |> validate_required([:provider, :image, :cpu_cores, :memory_mb, :disk_gb])
    |> validate_inclusion(:provider, ["firecracker", "cloud_hypervisor", "fly", "aws"])
    |> validate_number(:cpu_cores, greater_than: 0, less_than_or_equal_to: 128)
    |> validate_number(:memory_mb, greater_than: 0)
    |> validate_number(:disk_gb, greater_than: 0)
    |> validate_number(:ttl_seconds, greater_than: 0)
    |> validate_length(:image, min: 1, max: 200)
    |> validate_volume_names_unique()
  end

  defp validate_volume_names_unique(changeset) do
    volumes = get_field(changeset, :volumes, [])

    duplicates =
      volumes
      |> Enum.map(& &1.name)
      |> Enum.reject(&is_nil/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    if duplicates == [] do
      changeset
    else
      add_error(changeset, :volumes, "volume names must be unique")
    end
  end
end
