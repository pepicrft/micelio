defmodule MicelioWeb.LocalePlug do
  @moduledoc """
  Plug for handling locale detection and setting.

  For marketing pages (unauthenticated):
  - Detects locale from URL path prefix (e.g., /es/about)
  - Falls back to session, then Accept-Language header
  - Stores preference in session

  For dashboard pages (authenticated):
  - Uses user's locale preference from their account
  - Falls back to session, then Accept-Language header
  """

  import Plug.Conn
  use Gettext, backend: MicelioWeb.Gettext

  @default_locale "en"
  @supported_locales ~w(en ko zh_CN zh_TW ja)

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = detect_locale(conn)
    Gettext.put_locale(MicelioWeb.Gettext, locale)

    conn
    |> put_session(:locale, locale)
    |> assign(:locale, locale)
  end

  @doc """
  Detects locale from various sources in order of priority:
  1. URL path prefix (for locale-prefixed routes)
  2. User preference (for authenticated users)
  3. Session
  4. Accept-Language header
  5. Default locale
  """
  def detect_locale(conn) do
    [
      &locale_from_path/1,
      &locale_from_user/1,
      &locale_from_session/1,
      &locale_from_header/1
    ]
    |> Enum.find_value(fn detector -> detector.(conn) end)
    |> Kernel.||(@default_locale)
  end

  defp locale_from_path(%{path_info: [locale | _rest]}) when locale in @supported_locales do
    locale
  end

  defp locale_from_path(_conn), do: nil

  defp locale_from_user(%{assigns: %{current_user: %{locale: locale}}})
       when is_binary(locale) and locale in @supported_locales do
    locale
  end

  defp locale_from_user(_conn), do: nil

  defp locale_from_session(conn) do
    locale = get_session(conn, :locale)
    if locale in @supported_locales, do: locale
  end

  defp locale_from_header(conn) do
    conn
    |> get_req_header("accept-language")
    |> parse_accept_language()
    |> find_best_locale()
  end

  defp parse_accept_language([]) do
    []
  end

  defp parse_accept_language([header | _]) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, q} -> -q end)
    |> Enum.map(fn {lang, _q} -> lang end)
  end

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang] ->
        {normalize_language(lang), 1.0}

      [lang, "q=" <> q] ->
        case Float.parse(q) do
          {quality, _} -> {normalize_language(lang), quality}
          :error -> {normalize_language(lang), 0.0}
        end

      _ ->
        {"", 0.0}
    end
  end

  defp normalize_language(lang) do
    lang
    |> String.trim()
    |> String.downcase()
    |> String.split("-")
    |> List.first()
  end

  defp find_best_locale(languages) do
    Enum.find(languages, fn lang -> lang in @supported_locales end)
  end

  @doc """
  Returns the list of supported locales.
  """
  def supported_locales, do: @supported_locales

  @doc """
  Returns the default locale.
  """
  def default_locale, do: @default_locale
end
