defmodule Micelio.Handles do
  @moduledoc """
  Reserved handles that cannot be used by accounts.
  """

  @reserved [
    "settings",
    "micelio",
    "admin",
    "api",
    "auth",
    "login",
    "logout",
    "signup",
    "register",
    "help",
    "about",
    "contact",
    "terms",
    "privacy",
    "explore",
    "search",
    "new",
    "edit",
    "delete",
    "create",
    "update"
  ]

  @doc """
  Returns the list of reserved handles.
  """
  def reserved do
    @reserved
  end
end
