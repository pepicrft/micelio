defmodule Micelio.Accounts do
  alias Micelio.Accounts.Account

  @spec account(%{handle: String.t()}) :: {:ok, Account.t()} | {:error, :not_found}
  def account(%{handle: handle}) do
    # TODO: Fetch in the DB
    {:ok, %Account{handle: handle}}
  end
end
