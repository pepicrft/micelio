defmodule MicelioWeb.ReesourcePlug do
  def init(opts) do
    opts
  end

  def call(%{params: %{"account" => account_handle}} = conn, :load_account) do
    {:ok, account} = Micelio.Accounts.account(%{handle: account_handle})
    conn |> Plug.Conn.assign(:selected_account, account)
  end

  def call(conn, :load_account), do: conn

  def call(%{params: %{"repository" => repository_handle}} = conn, :load_repository) do
    {:ok, repository} = Micelio.Repositories.repository(%{handle: repository_handle})
    conn |> Plug.Conn.assign(:selected_repository, repository)
  end

  def call(conn, :load_repository) do
    conn
  end
end
