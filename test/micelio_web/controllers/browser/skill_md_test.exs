defmodule MicelioWeb.Browser.SkillMdTest do
  use MicelioWeb.ConnCase, async: true

  test "serves the agent skill guide", %{conn: conn} do
    conn = get(conn, "/skill.md")

    assert conn.status == 200
    assert response(conn, 200) =~ "# Micelio for AI Agents"
    assert response(conn, 200) =~ "Micelio Project Context"
    assert response(conn, 200) =~ "mix precommit"
  end

  test "agent guide stays aligned with AGENTS.md" do
    agents_path = Path.expand("AGENTS.md", File.cwd!())
    skill_path = Path.expand("priv/static/skill.md", File.cwd!())

    assert File.read!(agents_path) == File.read!(skill_path)
  end
end
