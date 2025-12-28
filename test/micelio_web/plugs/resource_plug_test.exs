defmodule MicelioWeb.ReesourcePlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest

  describe "load_account" do
    test "assigns the account if it exists" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_account)
      account = %Micelio.Accounts.Account{handle: "micelio"}
      expect(Micelio.Accounts, :account, fn %{handle: "micelio"} -> {:ok, account} end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_account] == account
    end

    test "doesn't assign the account if it doesn't exist" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_account)
      expect(Micelio.Accounts, :account, fn %{handle: "micelio"} -> {:error, :not_found} end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_account] == nil
    end
  end

  describe "load_repository" do
    test "assigns the repository if it exists" do
      conn = build_conn(:get, "/micelio/micelio", %{account: "micelio", repository: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)
      repository = %Micelio.Repositories.Repository{handle: "micelio"}
      expect(Micelio.Repositories, :repository, fn %{handle: "micelio"} -> {:ok, repository} end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == repository
    end

    test "doesn't assign the repository if it doesn't exist" do
      conn = build_conn(:get, "/micelio/micelio", %{account: "micelio", repository: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)

      expect(Micelio.Repositories, :repository, fn %{handle: "micelio"} ->
        {:error, :not_found}
      end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == nil
    end
  end
end
