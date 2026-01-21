defmodule MicelioWeb.ResourcePlugTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use ExUnit.Case, async: false
  use Mimic

  import Mimic
  import Phoenix.ConnTest

  setup :verify_on_exit!
  setup :set_mimic_global

  describe "load_account" do
    test "assigns the account if it exists" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ResourcePlug.init(:load_account)
      account = %Micelio.Accounts.Account{handle: "micelio"}
      expect(Micelio.Accounts, :get_account_by_handle, fn "micelio" -> account end)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_account] == account
    end
  end

  describe "load_project" do
    test "assigns nil when no project param" do
      conn = build_conn(:get, "/micelio", %{account: "micelio"})
      opts = MicelioWeb.ResourcePlug.init(:load_project)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_project] == nil
      assert Map.delete(got.assigns, :selected_project) == conn.assigns
    end

    test "loads project when account and project param exist" do
      conn = build_conn(:get, "/micelio/mic", %{account: "micelio", project: "mic"})
      opts = MicelioWeb.ResourcePlug.init(:load_project)

      account = %Micelio.Accounts.Account{handle: "micelio", organization_id: "org-1"}
      conn = Plug.Conn.assign(conn, :selected_account, account)

      project = %Micelio.Projects.Project{handle: "mic", organization_id: "org-1"}
      expect(Micelio.Projects, :get_project_by_handle, fn "org-1", "mic" -> project end)

      got = MicelioWeb.ResourcePlug.call(conn, opts)

      assert got.assigns[:selected_project] == project
    end
  end
end
