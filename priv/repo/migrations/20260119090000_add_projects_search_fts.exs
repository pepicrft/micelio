defmodule Micelio.Repo.Migrations.AddProjectsSearchFts do
  use Ecto.Migration

  def up do
    execute("""
    CREATE VIRTUAL TABLE projects_fts USING fts5(
      project_id UNINDEXED,
      name,
      description,
      tokenize = 'porter'
    );
    """)

    execute("""
    INSERT INTO projects_fts(project_id, name, description)
    SELECT id, name, coalesce(description, '') FROM projects;
    """)

    execute("""
    CREATE TRIGGER projects_fts_insert AFTER INSERT ON projects BEGIN
      INSERT INTO projects_fts(project_id, name, description)
      VALUES (new.id, new.name, coalesce(new.description, ''));
    END;
    """)

    execute("""
    CREATE TRIGGER projects_fts_delete AFTER DELETE ON projects BEGIN
      DELETE FROM projects_fts WHERE project_id = old.id;
    END;
    """)

    execute("""
    CREATE TRIGGER projects_fts_update AFTER UPDATE ON projects BEGIN
      DELETE FROM projects_fts WHERE project_id = old.id;
      INSERT INTO projects_fts(project_id, name, description)
      VALUES (new.id, new.name, coalesce(new.description, ''));
    END;
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS projects_fts_insert;")
    execute("DROP TRIGGER IF EXISTS projects_fts_delete;")
    execute("DROP TRIGGER IF EXISTS projects_fts_update;")
    execute("DROP TABLE IF EXISTS projects_fts;")
  end
end
