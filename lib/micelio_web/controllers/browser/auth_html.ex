defmodule MicelioWeb.Browser.AuthHTML do
  @moduledoc """
  HTML templates for authentication pages.
  """

  use MicelioWeb, :html

  import MicelioWeb.CoreComponents

  embed_templates "auth_html/*"
end
