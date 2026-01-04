defmodule Micelio.Accounts.AuthEmail do
  @moduledoc """
  Email templates for authentication.
  """

  import Swoosh.Email

  @from {"Micelio", "noreply@micelio.dev"}

  @doc """
  Builds the magic link login email.
  """
  def login_email(user, login_url) do
    new()
    |> to(user.email)
    |> from(@from)
    |> subject("Sign in to Micelio")
    |> html_body(login_html(login_url))
    |> text_body(login_text(login_url))
  end

  defp login_html(url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .button { display: inline-block; background: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 20px 0; }
        .footer { margin-top: 30px; font-size: 12px; color: #666; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Sign in to Micelio</h1>
        <p>Click the button below to sign in to your account. This link will expire in 15 minutes.</p>
        <a href="#{url}" class="button">Sign in to Micelio</a>
        <p>Or copy and paste this link into your browser:</p>
        <p><code>#{url}</code></p>
        <div class="footer">
          <p>If you didn't request this email, you can safely ignore it.</p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp login_text(url) do
    """
    Sign in to Micelio

    Click the link below to sign in to your account. This link will expire in 15 minutes.

    #{url}

    If you didn't request this email, you can safely ignore it.
    """
  end
end
