defmodule Micelio.Accounts do
  alias Micelio.Accounts.Account

  def account(%{handle: handle}) do
    # TODO: Fetch in the DB
    {:ok, %Account{handle: handle}}
  end
end
