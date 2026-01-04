defmodule MicelioWeb.ErrorJSON do
  @moduledoc """
  JSON error responses.
  """

  def render("404.json", _assigns) do
    %{errors: %{detail: "Not Found"}}
  end

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal Server Error"}}
  end

  def error(%{message: message}) do
    %{errors: %{detail: message}}
  end
end
