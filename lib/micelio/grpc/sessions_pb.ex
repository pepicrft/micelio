defmodule Micelio.GRPC.Sessions.V1.ConversationMessage do
  use Protobuf, syntax: :proto3

  field :role, 1, type: :string
  field :content, 2, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.Decision do
  use Protobuf, syntax: :proto3

  field :decision, 1, type: :string
  field :reasoning, 2, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.FileChange do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :content, 2, type: :string
  field :change_type, 3, type: :string, json_name: "changeType"
end

defmodule Micelio.GRPC.Sessions.V1.Session do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :goal, 3, type: :string
  field :organization_handle, 4, type: :string, json_name: "organizationHandle"
  field :project_handle, 5, type: :string, json_name: "projectHandle"
  field :status, 6, type: :string
  field :conversation_count, 7, type: :uint32, json_name: "conversationCount"
  field :decisions_count, 8, type: :uint32, json_name: "decisionsCount"
  field :started_at, 9, type: :string, json_name: "startedAt"
  field :landed_at, 10, type: :string, json_name: "landedAt"
  field :landing_position, 11, type: :uint64, json_name: "landingPosition"
end

defmodule Micelio.GRPC.Sessions.V1.StartSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
  field :session_id, 4, type: :string, json_name: "sessionId"
  field :goal, 5, type: :string
  field :conversation, 6, repeated: true, type: Micelio.GRPC.Sessions.V1.ConversationMessage
  field :decisions, 7, repeated: true, type: Micelio.GRPC.Sessions.V1.Decision
end

defmodule Micelio.GRPC.Sessions.V1.LandSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :conversation, 3, repeated: true, type: Micelio.GRPC.Sessions.V1.ConversationMessage
  field :decisions, 4, repeated: true, type: Micelio.GRPC.Sessions.V1.Decision
  field :files, 5, repeated: true, type: Micelio.GRPC.Sessions.V1.FileChange
  field :epoch, 6, type: :uint32
  field :finalize, 7, type: :bool
end

defmodule Micelio.GRPC.Sessions.V1.GetSessionRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :session_id, 2, type: :string, json_name: "sessionId"
end

defmodule Micelio.GRPC.Sessions.V1.ListSessionsRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :organization_handle, 2, type: :string, json_name: "organizationHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
  field :status, 4, type: :string
  field :path, 5, type: :string
end

defmodule Micelio.GRPC.Sessions.V1.SessionResponse do
  use Protobuf, syntax: :proto3

  field :session, 1, type: Micelio.GRPC.Sessions.V1.Session
end

defmodule Micelio.GRPC.Sessions.V1.ListSessionsResponse do
  use Protobuf, syntax: :proto3

  field :sessions, 1, repeated: true, type: Micelio.GRPC.Sessions.V1.Session
end

defmodule Micelio.GRPC.Sessions.V1.SessionService.Service do
  use GRPC.Service, name: "micelio.sessions.v1.SessionService"

  rpc(
    :StartSession,
    Micelio.GRPC.Sessions.V1.StartSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :LandSession,
    Micelio.GRPC.Sessions.V1.LandSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :GetSession,
    Micelio.GRPC.Sessions.V1.GetSessionRequest,
    Micelio.GRPC.Sessions.V1.SessionResponse
  )

  rpc(
    :ListSessions,
    Micelio.GRPC.Sessions.V1.ListSessionsRequest,
    Micelio.GRPC.Sessions.V1.ListSessionsResponse
  )
end
