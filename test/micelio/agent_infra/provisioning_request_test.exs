defmodule Micelio.AgentInfra.ProvisioningRequestTest do
  use Micelio.DataCase, async: true

  alias Micelio.AgentInfra
  alias Micelio.AgentInfra.ProvisioningRequest

  test "from_plan/1 normalizes volume read_only values" do
    attrs = %{
      provider: "firecracker",
      image: "micelio/agent-runner:latest",
      cpu_cores: 4,
      memory_mb: 4096,
      disk_gb: 50,
      network: "isolated",
      ttl_seconds: 900,
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace",
          access: "ro"
        },
        %{
          name: "cache",
          source: "/var/lib/micelio/cache",
          target: "/cache",
          type: "bind",
          access: "rw"
        }
      ]
    }

    assert {:ok, plan} = AgentInfra.build_plan(attrs)
    request = ProvisioningRequest.from_plan(plan)

    assert %ProvisioningRequest{
             provider: "firecracker",
             image: "micelio/agent-runner:latest",
             cpu_cores: 4,
             memory_mb: 4096,
             disk_gb: 50,
             network: "isolated",
             ttl_seconds: 900
           } = request

    assert request.volumes == [
             %{
               name: "workspace",
               type: "volume",
               source: "agent-workspace",
               target: "/workspace",
               read_only: true
             },
             %{
               name: "cache",
               type: "bind",
               source: "/var/lib/micelio/cache",
               target: "/cache",
               read_only: false
             }
           ]
  end

  test "build_request/1 returns a request after validation" do
    attrs = %{
      provider: "fly",
      image: "micelio/agent-runner:latest",
      cpu_cores: 2,
      memory_mb: 2048,
      disk_gb: 20,
      volumes: [
        %{
          name: "workspace",
          source: "agent-workspace",
          target: "/workspace"
        }
      ]
    }

    assert {:ok, %ProvisioningRequest{provider: "fly"}} = AgentInfra.build_request(attrs)
  end
end
