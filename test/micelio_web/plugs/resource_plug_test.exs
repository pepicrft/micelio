defmodule MicelioWeb.ReesourcePlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Phoenix.ConnTest

  describe "load_account" do
    test "assigns the account if it exists" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_account)
      account = %Micelio.Accounts.Account{handle: "micelio"}
      expect(Micelio.Accounts, :get_account_by_handle, fn "micelio" -> account end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_account] == account
    end
  end

  describe "load_repository" do
    test "assigns the repository if it exists" do
      conn = build_conn(:get, "/micelio/micelio", %{account: "micelio", repository: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)
      repository = %Micelio.Repositories.Repository{handle: "micelio"}
      expect(Micelio.Repositories, :get_repository_by_handle, fn "micelio" -> repository end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == repository
    end
  end
end
