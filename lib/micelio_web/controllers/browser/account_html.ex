defmodule MicelioWeb.Browser.AccountHTML do
  use MicelioWeb, :html

  embed_templates "account_html/*"

  def activity_action_label(:session_landed), do: "Landed a session in"
  def activity_action_label(:project_starred), do: "Starred"
  def activity_action_label(:project_created), do: "Created project"
  def activity_action_label(_), do: "Updated"
end
