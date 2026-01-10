defmodule MicelioWeb.Browser.AuthController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Accounts.AuthEmail
  alias Micelio.Mailer

  require Logger

  @doc """
  Renders the login form.
  """
  def new(conn, _params) do
    render(conn, :new)
  end

  @doc """
  Handles the login form submission.
  Sends a magic link email to the user.
  """
  def create(conn, %{"email" => email}) do
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
    render(conn, :sent)
  end

  @doc """
  Verifies the magic link token and logs the user in.
  """
  def verify(conn, %{"token" => token}) do
    case Accounts.verify_login_token(token) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Welcome back, #{user.account.handle}!")
        |> redirect(to: ~p"/")

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
      match?(%Swoosh.Error{}, reason) ->
        error = reason

        details ++
          [
            error: Exception.message(error),
            swoosh_reason: inspect(error.reason, pretty: true, limit: :infinity)
          ]

      match?(%{__exception__: true}, reason) ->
        details ++ [error: Exception.message(reason)]

      true ->
        details
    end
  end
end
