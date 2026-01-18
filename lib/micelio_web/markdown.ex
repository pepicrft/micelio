defmodule MicelioWeb.Markdown do
  @moduledoc false

  @options [escape: true]

  @spec render(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def render(markdown) when is_binary(markdown) do
    case Earmark.as_html(markdown, @options) do
      {:ok, html, _messages} -> {:ok, html}
      {:error, html, _messages} -> {:error, html}
    end
  end
end
