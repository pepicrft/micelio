defmodule Micelio.GRPC.Endpoint do
  use GRPC.Endpoint

  run(Micelio.GRPC.Auth.V1.DeviceAuthService.Server)
  run(Micelio.GRPC.Projects.V1.ProjectService.Server)
  run(Micelio.GRPC.Content.V1.ContentService.Server)
  run(Micelio.GRPC.Sessions.V1.SessionService.Server)
end
