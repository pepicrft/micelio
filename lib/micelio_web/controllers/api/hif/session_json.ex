defmodule MicelioWeb.API.Hif.SessionJSON do
  @moduledoc """
  JSON rendering for hif sessions.
  """

  alias Micelio.Hif.Session

  @doc """
  Renders a list of sessions.
  """
  def index(%{sessions: sessions}) do
    %{data: for(session <- sessions, do: data(session))}
  end

  @doc """
  Renders a single session.
  """
  def show(%{session: session}) do
    %{data: data(session)}
  end

  defp data(%Session{} = session) do
    %{
      id: session.id,
      goal: session.goal,
      state: session.state,
      project_id: session.project_id,
      user_id: session.user_id,
      decisions: session.decisions,
      conversation: session.conversation,
      operations: session.operations,
      landed_at: session.landed_at,
      inserted_at: session.inserted_at,
      updated_at: session.updated_at
    }
  end
end
