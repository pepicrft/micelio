defmodule MicelioWeb.ReesourcePlug do
  def init(opts) do
    opts
  end

  def call(%{params: %{"account" => account_handle}} = conn, :load_account) do
    case Micelio.Accounts.account(%{handle: account_handle}) do
      {:ok, account} -> conn |> Plug.Conn.assign(:selected_account, account)
      {:error, _} -> conn
    end
  end

  def call(conn, :load_account), do: conn

  def call(%{params: %{"repository" => repository_handle}} = conn, :load_repository) do
    case Micelio.Repositories.repository(%{handle: repository_handle}) do
      {:ok, repository} -> conn |> Plug.Conn.assign(:selected_repository, repository)
      {:error, _} -> conn
    end
  end

  def call(conn, :load_repository) do
    conn
  end
end
