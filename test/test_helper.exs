Mimic.copy(Micelio.Accounts)
Mimic.copy(Micelio.Repositories)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Micelio.Repo, :manual)
