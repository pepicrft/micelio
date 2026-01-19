defmodule MicelioWeb.Browser.AuthController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.Accounts
  alias Micelio.Accounts.AuthEmail
  alias Micelio.Auth.GitHub
  alias Micelio.Auth.GitLab
  alias Micelio.Mailer
  alias MicelioWeb.PageMeta

  require Logger

  @doc """
  Renders the login form.
  """
  def new(conn, params) do
    email = Map.get(params, "email", "")
    form = to_form(%{"email" => email}, as: :login)

    conn
    |> PageMeta.put(
      title_parts: ["Log in"],
      description: "Log in to Micelio.",
      canonical_url: url(~p"/auth/login")
    )
    |> render(:new, form: form)
  end

  @doc """
  Handles the login form submission.
  Sends a magic link email to the user.
  """
  def create(conn, %{"login" => %{"email" => email}}) do
    handle_login(conn, email)
  end

  def create(conn, %{"email" => email}) do
    handle_login(conn, email)
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "Please enter a valid email.")
    |> redirect(to: ~p"/auth/login")
  end

  defp handle_login(conn, email) do
    case Accounts.initiate_login(email) do
      {:ok, login_token} ->
        login_url = url(~p"/auth/verify/#{login_token.token}")

        email =
          login_token.user
          |> AuthEmail.login_email(login_url)

        case Mailer.deliver(email) do
          {:ok, _response} ->
            Logger.info("Login email delivered",
              user_id: login_token.user.id,
              email: login_token.user.email
            )

          {:error, reason} ->
            Logger.error(
              "Login email delivery failed",
              [user_id: login_token.user.id, email: login_token.user.email] ++
                delivery_error_metadata(reason)
            )
        end

        conn
        |> put_flash(:info, "Check your email for a login link!")
        |> redirect(to: ~p"/auth/sent")

      {:error, reason} ->
        Logger.warning("Login email initiation failed",
          email: email,
          reason: inspect(reason)
        )

        conn
        |> put_flash(:error, "Something went wrong. Please try again.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Renders the "check your email" page.
  """
  def sent(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Check your email"],
      description: "We sent you a login link. Check your inbox to continue.",
      canonical_url: url(~p"/auth/sent")
    )
    |> render(:sent)
  end

  @doc """
  Redirects the user to GitHub for OAuth authentication.
  """
  def github_start(conn, _params) do
    state = generate_oauth_state()

    case GitHub.authorize_url(state) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:github_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, reason} ->
        Logger.warning("GitHub OAuth not configured", reason: inspect(reason))

        conn
        |> put_flash(:error, "GitHub login is not available right now.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Redirects the user to GitLab for OAuth authentication.
  """
  def gitlab_start(conn, _params) do
    state = generate_oauth_state()

    case GitLab.authorize_url(state) do
      {:ok, authorize_url} ->
        conn
        |> put_session(:gitlab_oauth_state, state)
        |> redirect(external: authorize_url)

      {:error, reason} ->
        Logger.warning("GitLab OAuth not configured", reason: inspect(reason))

        conn
        |> put_flash(:error, "GitLab login is not available right now.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Handles the GitHub OAuth callback and signs the user in.
  """
  def github_callback(conn, %{"error" => error}) do
    Logger.warning("GitHub OAuth callback error", error: error)

    conn
    |> put_flash(:error, "GitHub login failed. Please try again.")
    |> redirect(to: ~p"/auth/login")
  end

  def github_callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :github_oauth_state)

    if session_state == state and is_binary(session_state) do
      conn = delete_session(conn, :github_oauth_state)

      with {:ok, profile} <- GitHub.fetch_user_profile(code),
           {:ok, user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email
             ) do
        maybe_require_totp(conn, user)
      else
        {:error, reason} ->
          Logger.warning("GitHub OAuth callback failed", reason: inspect(reason))

          conn
          |> put_flash(:error, "GitHub login failed. Please try again.")
          |> redirect(to: ~p"/auth/login")
      end
    else
      conn
      |> put_flash(:error, "GitHub login failed. Please try again.")
      |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Handles the GitLab OAuth callback and signs the user in.
  """
  def gitlab_callback(conn, %{"error" => error}) do
    Logger.warning("GitLab OAuth callback error", error: error)

    conn
    |> put_flash(:error, "GitLab login failed. Please try again.")
    |> redirect(to: ~p"/auth/login")
  end

  def gitlab_callback(conn, %{"code" => code, "state" => state}) do
    session_state = get_session(conn, :gitlab_oauth_state)

    if session_state == state and is_binary(session_state) do
      conn = delete_session(conn, :gitlab_oauth_state)

      with {:ok, profile} <- GitLab.fetch_user_profile(code),
           {:ok, user} <-
             Accounts.get_or_create_user_from_oauth(
               profile.provider,
               profile.provider_user_id,
               profile.email
             ) do
        maybe_require_totp(conn, user)
      else
        {:error, reason} ->
          Logger.warning("GitLab OAuth callback failed", reason: inspect(reason))

          conn
          |> put_flash(:error, "GitLab login failed. Please try again.")
          |> redirect(to: ~p"/auth/login")
      end
    else
      conn
      |> put_flash(:error, "GitLab login failed. Please try again.")
      |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Verifies the magic link token and logs the user in.
  """
  def verify(conn, %{"token" => token}) do
    case Accounts.verify_login_token(token) do
      {:ok, user} ->
        maybe_require_totp(conn, user)

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "This login link is invalid or has expired.")
        |> redirect(to: ~p"/auth/login")
    end
  end

  @doc """
  Logs the user out.
  """
  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end

  defp delivery_error_metadata(reason) do
    details = [reason: inspect(reason, pretty: true, limit: :infinity)]

    cond do
      is_map(reason) and Map.get(reason, :__struct__) == Swoosh.Error ->
        details ++
          [
            error: Exception.message(reason),
            swoosh_reason: inspect(Map.get(reason, :reason), pretty: true, limit: :infinity)
          ]

      match?(%{__exception__: true}, reason) ->
        details ++ [error: Exception.message(reason)]

      true ->
        details
    end
  end

  defp login_redirect_path(conn) do
    if get_session(conn, :device_user_code) do
      ~p"/device/auth"
    else
      ~p"/"
    end
  end

  defp maybe_require_totp(conn, user) do
    if Accounts.totp_enabled?(user) do
      conn
      |> put_session(:totp_pending_user_id, user.id)
      |> put_session(:totp_pending_redirect, login_redirect_path(conn))
      |> redirect(to: ~p"/auth/totp")
    else
      conn
      |> put_session(:user_id, user.id)
      |> put_flash(:info, "Welcome back, #{user.account.handle}!")
      |> redirect(to: login_redirect_path(conn))
    end
  end

  defp generate_oauth_state do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
