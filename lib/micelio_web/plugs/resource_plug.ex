defmodule MicelioWeb.ReesourcePlug do
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%{params: %{"account" => account_handle}} = conn, :load_account) do
    account = Micelio.Accounts.get_account_by_handle(account_handle)
    conn |> assign(:selected_account, account)
  end

  def call(conn, :load_account), do: conn

  def call(conn, :load_repository) do
    conn
  end
end
