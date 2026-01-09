defmodule MicelioWeb.Browser.AuthController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Accounts.AuthEmail
  alias Micelio.Mailer

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

        email_result =
          login_token.user
          |> AuthEmail.login_email(login_url)
          |> Mailer.deliver()

        require Logger
        Logger.info("Email delivery result: #{inspect(email_result)}")

        conn
        |> put_flash(:info, "Check your email for a login link!")
        |> redirect(to: ~p"/auth/sent")

      {:error, _reason} ->
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
end
