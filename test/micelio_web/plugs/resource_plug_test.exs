defmodule MicelioWeb.ReesourcePlugTest do
  use ExUnit.Case, async: true
  use Mimic

  import Mimic
  import Phoenix.ConnTest

  setup :verify_on_exit!

  setup_all do
    Mimic.copy(Micelio.Projects)
    :ok
  end

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
    test "assigns nil when no repository param" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == nil
      assert Map.delete(got.assigns, :selected_repository) == conn.assigns
    end

    test "loads repository when account and repository param exist" do
      conn = build_conn(:get, "/micelio/mic", %{account: "micelio", repository: "mic"})
      opts = MicelioWeb.ReesourcePlug.init(:load_repository)

      account = %Micelio.Accounts.Account{handle: "micelio", organization_id: "org-1"}
      conn = Plug.Conn.assign(conn, :selected_account, account)

      repository = %Micelio.Projects.Project{handle: "mic", organization_id: "org-1"}
      expect(Micelio.Projects, :get_project_by_handle, fn "org-1", "mic" -> repository end)

      got = MicelioWeb.ReesourcePlug.call(conn, opts)

      assert got.assigns[:selected_repository] == repository
    end
  end
end
