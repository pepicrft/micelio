defmodule MicelioWeb.SessionLiveTest do
  use MicelioWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Micelio.{Accounts, Projects, Sessions}
  alias Micelio.Sessions.OGSummary

  describe "SessionLive.Index" do
    setup :register_and_log_in_user
    setup :create_project

    test "lists all sessions", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, _} =
        Sessions.create_session(%{
          session_id: "session-1",
          goal: "Build authentication",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _} =
        Sessions.create_session(%{
          session_id: "session-2",
          goal: "Add real-time features",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _index_live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{project.handle}/sessions")

      assert html =~ "Sessions"
      assert html =~ "Build authentication"
      assert html =~ "Add real-time features"
    end

    test "displays session metadata", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, _session} =
        Sessions.create_session(%{
          session_id: "test-session",
          goal: "Test goal",
          project_id: project.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "Message 1"},
            %{"role" => "assistant", "content" => "Message 2"}
          ],
          decisions: [
            %{"decision" => "Decision 1", "reasoning" => "Because"}
          ]
        })

      {:ok, _live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{project.handle}/sessions")

      assert html =~ "2 messages"
      assert html =~ "1 decisions"
    end

    test "filters sessions by status", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, _active_session} =
        Sessions.create_session(%{
          session_id: "active",
          goal: "Active session",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, landed_session} =
        Sessions.create_session(%{
          session_id: "landed",
          goal: "Landed session",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _} = Sessions.land_session(landed_session)

      {:ok, index_live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{project.handle}/sessions")

      assert html =~ "Active session"
      assert html =~ "Landed session"

      # Filter by active
      html = index_live |> element("button", "Active") |> render_click()
      assert html =~ "Active session"
      refute html =~ "Landed session"

      # Filter by landed
      html = index_live |> element("button", "Landed") |> render_click()
      refute html =~ "Active session"
      assert html =~ "Landed session"

      # Show all
      html = index_live |> element("button", "All") |> render_click()
      assert html =~ "Active session"
      assert html =~ "Landed session"
    end

    test "shows empty state when no sessions exist", %{
      conn: conn,
      project: project,
      organization: organization
    } do
      {:ok, _live, html} =
        live(conn, "/projects/#{organization.account.handle}/#{project.handle}/sessions")

      assert html =~ "No sessions found"
    end

    test "requires authentication", %{conn: conn, project: project, organization: organization} do
      conn = conn |> log_out_user()

      assert {:error, {:redirect, %{to: "/auth/login"}}} =
               live(conn, "/projects/#{organization.account.handle}/#{project.handle}/sessions")
    end
  end

  describe "SessionLive.Show" do
    setup :register_and_log_in_user
    setup :create_project

    test "displays session details", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "detail-session",
          goal: "Build something great",
          project_id: project.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "Hello"},
            %{"role" => "assistant", "content" => "Hi there"}
          ],
          decisions: [
            %{"decision" => "Use Phoenix", "reasoning" => "Best framework"}
          ],
          metadata: %{
            "custom_key" => "custom_value"
          }
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      assert html =~ "Build something great"
      assert html =~ "Hello"
      assert html =~ "Hi there"
      assert html =~ "Use Phoenix"
      assert html =~ "Best framework"
      assert html =~ "custom_key"
    end

    test "displays conversation with role labels", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "conversation-test",
          goal: "Test conversation display",
          project_id: project.id,
          user_id: user.id,
          conversation: [
            %{"role" => "user", "content" => "User message"},
            %{"role" => "assistant", "content" => "Assistant message"},
            %{"role" => "system", "content" => "System message"}
          ]
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      assert html =~ "User"
      assert html =~ "Assistant"
      assert html =~ "System"
      assert html =~ "User message"
      assert html =~ "Assistant message"
      assert html =~ "System message"
    end

    test "shows abandon button for active sessions", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "active-session",
          goal: "Active",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      assert html =~ "Abandon Session"
      refute html =~ "Delete Session"
    end

    test "shows delete button for landed sessions", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "landed-session",
          goal: "Landed",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, landed_session} = Sessions.land_session(session)

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{landed_session.id}"
        )

      assert html =~ "Delete Session"
      refute html =~ "Abandon Session"
    end

    test "abandons an active session", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-abandon",
          goal: "Will be abandoned",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, show_live, _html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      html = show_live |> element("button", "Abandon Session") |> render_click()

      assert html =~ "Session abandoned successfully"
      assert html =~ "Abandoned"

      # Verify in database
      abandoned_session = Sessions.get_session(session.id)
      assert abandoned_session.status == "abandoned"
    end

    test "deletes a landed session", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "to-delete",
          goal: "Will be deleted",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, landed} = Sessions.land_session(session)

      {:ok, show_live, _html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{landed.id}"
        )

      show_live |> element("button", "Delete Session") |> render_click()

      # Should redirect to sessions list
      assert_redirect(
        show_live,
        "/projects/#{organization.account.handle}/#{project.handle}/sessions"
      )

      # Verify deleted from database
      assert Sessions.get_session(session.id) == nil
    end

    test "shows empty state when no file changes", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "files-test",
          goal: "Test files",
          project_id: project.id,
          user_id: user.id,
          metadata: %{"files_count" => 5}
        })

      {:ok, _live, html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      assert html =~ "Changes"
      assert html =~ "No file changes in this session"
    end

    test "uses cached og summary for page meta description", %{
      conn: conn,
      project: project,
      user: user,
      organization: organization
    } do
      {:ok, session} =
        Sessions.create_session(%{
          session_id: "og-summary-session",
          goal: "Summarize OG",
          project_id: project.id,
          user_id: user.id
        })

      {:ok, _change} =
        Sessions.create_session_change(%{
          session_id: session.id,
          file_path: "lib/micelio/example.ex",
          change_type: "modified",
          content: "updated"
        })

      changes = Sessions.list_session_changes(session)
      summary = "Updated example module to refine session behavior."
      digest = OGSummary.digest(changes)

      {:ok, _session} =
        Sessions.update_session(session, %{
          metadata: %{"og_summary" => summary, "og_summary_hash" => digest}
        })

      {:ok, view, _html} =
        live(
          conn,
          "/projects/#{organization.account.handle}/#{project.handle}/sessions/#{session.id}"
        )

      assert %MicelioWeb.PageMeta{description: ^summary} = view.assigns.page_meta
    end

    test "returns 404 for non-existent session", %{
      conn: conn,
      project: project,
      organization: organization
    } do
      assert {:error,
              {:live_redirect, %{to: redirect_to, flash: %{"error" => "Session not found."}}}} =
               live(
                 conn,
                 "/projects/#{organization.account.handle}/#{project.handle}/sessions/00000000-0000-0000-0000-000000000000"
               )

      assert redirect_to == "/projects/#{organization.account.handle}/#{project.handle}/sessions"
    end

    test "requires authentication", %{conn: conn, project: project, organization: organization} do
      conn = conn |> log_out_user()

      assert {:error, {:redirect, %{to: "/auth/login"}}} =
               live(
                 conn,
                 "/projects/#{organization.account.handle}/#{project.handle}/sessions/123"
               )
    end
  end

  defp create_project(%{user: user}) do
    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "test-org",
        name: "Test Organization"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "test-project",
        name: "Test Project",
        description: "A test project",
        organization_id: organization.id
      })

    %{project: project, organization: organization}
  end

  defp log_out_user(conn) do
    conn
    |> Phoenix.ConnTest.delete(~p"/auth/logout")
    |> Phoenix.ConnTest.recycle()
  end
end
