defmodule Micelio.GRPC.Content.V1.TreeEntry do
  use Protobuf, syntax: :proto3

  field :path, 1, type: :string
  field :hash, 2, type: :bytes
end

defmodule Micelio.GRPC.Content.V1.Tree do
  use Protobuf, syntax: :proto3

  field :entries, 1, repeated: true, type: Micelio.GRPC.Content.V1.TreeEntry
end

defmodule Micelio.GRPC.Content.V1.GetHeadTreeRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :account_handle, 2, type: :string, json_name: "accountHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
end

defmodule Micelio.GRPC.Content.V1.GetTreeRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :account_handle, 2, type: :string, json_name: "accountHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
  field :tree_hash, 4, type: :bytes, json_name: "treeHash"
end

defmodule Micelio.GRPC.Content.V1.GetTreeResponse do
  use Protobuf, syntax: :proto3

  field :tree, 1, type: Micelio.GRPC.Content.V1.Tree
  field :tree_hash, 2, type: :bytes, json_name: "treeHash"
end

defmodule Micelio.GRPC.Content.V1.GetBlobRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :account_handle, 2, type: :string, json_name: "accountHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
  field :blob_hash, 4, type: :bytes, json_name: "blobHash"
end

defmodule Micelio.GRPC.Content.V1.GetBlobResponse do
  use Protobuf, syntax: :proto3

  field :content, 1, type: :bytes
end

defmodule Micelio.GRPC.Content.V1.GetPathRequest do
  use Protobuf, syntax: :proto3

  field :user_id, 1, type: :string, json_name: "userId"
  field :account_handle, 2, type: :string, json_name: "accountHandle"
  field :project_handle, 3, type: :string, json_name: "projectHandle"
  field :path, 4, type: :string
end

defmodule Micelio.GRPC.Content.V1.GetPathResponse do
  use Protobuf, syntax: :proto3

  field :content, 1, type: :bytes
  field :blob_hash, 2, type: :bytes, json_name: "blobHash"
end

defmodule Micelio.GRPC.Content.V1.ContentService.Service do
  use GRPC.Service, name: "micelio.content.v1.ContentService"

  rpc(
    :GetHeadTree,
    Micelio.GRPC.Content.V1.GetHeadTreeRequest,
    Micelio.GRPC.Content.V1.GetTreeResponse
  )

  rpc(
    :GetTree,
    Micelio.GRPC.Content.V1.GetTreeRequest,
    Micelio.GRPC.Content.V1.GetTreeResponse
  )

  rpc(
    :GetBlob,
    Micelio.GRPC.Content.V1.GetBlobRequest,
    Micelio.GRPC.Content.V1.GetBlobResponse
  )

  rpc(
    :GetPath,
    Micelio.GRPC.Content.V1.GetPathRequest,
    Micelio.GRPC.Content.V1.GetPathResponse
  )
end
