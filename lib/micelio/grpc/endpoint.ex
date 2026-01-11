defmodule Micelio.GRPC.Endpoint do
  use GRPC.Endpoint

  run Micelio.GRPC.Projects.V1.ProjectService.Server
end
