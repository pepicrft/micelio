defmodule MicelioWeb.ErrorCapturePlug do
  @moduledoc false

  use Plug.ErrorHandler

  import Plug.Conn

  alias Micelio.Errors.Capture

  def init(opts), do: opts

  def call(conn, _opts), do: conn

  def handle_errors(conn, %{kind: kind, reason: reason, stack: stacktrace}) do
    Capture.capture_exception(reason,
      kind: :plug_error,
      error_kind: kind,
      stacktrace: stacktrace,
      context: conn_context(conn),
      metadata: %{plug_kind: kind},
      source: :plug
    )
  end

  defp conn_context(conn) do
    %{
      request_id: conn.assigns[:request_id] || List.first(get_resp_header(conn, "x-request-id")),
      method: conn.method,
      path: conn.request_path
    }
  end
end
