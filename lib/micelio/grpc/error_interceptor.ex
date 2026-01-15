defmodule Micelio.GRPC.ErrorInterceptor do
  @moduledoc """
  gRPC server interceptor that converts {:error, %GRPC.RPCError{}} tuples
  returned from handlers into raised exceptions.

  This is needed because the GRPC library (as of v0.11.5) does not properly
  handle error tuples returned from server functions - it tries to encode
  them as protobuf messages instead of treating them as errors.

  Usage: Add this interceptor to your GRPC endpoint configuration.
  """

  @behaviour GRPC.Server.Interceptor

  @impl true
  def init(opts), do: opts

  @impl true
  def call(req, stream, next, _opts) do
    case next.(req, stream) do
      {:ok, _stream, {:error, %GRPC.RPCError{} = error}} ->
        raise error

      {:ok, _stream, {:error, error}} when is_exception(error) ->
        raise error

      other ->
        other
    end
  end
end
