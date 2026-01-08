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
    test "returns conn unchanged when no repository param" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got == conn
    end
  end
end
