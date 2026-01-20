defmodule MicelioWeb.ResourcePlug do
  import Plug.Conn

  alias Micelio.Accounts
  alias Micelio.Projects

  def init(opts) do
    opts
  end

  def call(%{params: %{"account" => account_handle}} = conn, :load_account) do
    account = Accounts.get_account_by_handle(account_handle)
    assign(conn, :selected_account, account)
  end

  def call(conn, :load_account), do: conn

  def call(conn, :load_project) do
    case conn do
      %{params: %{"project" => project_handle}, assigns: %{selected_account: account}}
      when not is_nil(account) ->
        project =
          if is_binary(account.organization_id) do
            Projects.get_project_by_handle(account.organization_id, project_handle)
          end

        assign(conn, :selected_project, project)

      _ ->
        assign(conn, :selected_project, nil)
    end
  end
end
