defmodule Micelio.Hif.Session do
  @moduledoc """
  Schema for hif sessions.

  A session represents a unit of work that captures:
  - Goal: what you're trying to accomplish
  - Decisions: why things were done a certain way
  - Conversation: discussion between agents and humans
  - Operations: file changes (write, delete, rename)

  Sessions follow a lifecycle:
  - active: work in progress
  - landed: changes merged into main
  - abandoned: work discarded
  - conflicted: needs conflict resolution
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type state :: :active | :landed | :abandoned | :conflicted
  @type t :: %__MODULE__{}

  @states ~w(active landed abandoned conflicted)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hif_sessions" do
    field :goal, :string
    field :state, :string, default: "active"
    field :decisions, {:array, :map}, default: []
    field :conversation, {:array, :map}, default: []
    field :operations, {:array, :map}, default: []
    field :landed_at, :utc_datetime_usec

    belongs_to :project, Micelio.Repositories.Repository
    belongs_to :user, Micelio.Accounts.Account

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new session.
  """
  @spec create_changeset(t(), map()) :: Ecto.Changeset.t()
  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:goal, :project_id, :user_id])
    |> validate_required([:goal, :project_id, :user_id])
    |> validate_length(:goal, min: 1, max: 1000)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating session state.
  """
  @spec state_changeset(t(), map()) :: Ecto.Changeset.t()
  def state_changeset(session, attrs) do
    session
    |> cast(attrs, [:state, :landed_at])
    |> validate_inclusion(:state, @states)
    |> validate_state_transition()
  end

  @doc """
  Changeset for adding a decision to the session.
  """
  @spec decision_changeset(t(), map()) :: Ecto.Changeset.t()
  def decision_changeset(session, decision) do
    decisions = session.decisions ++ [decision]

    session
    |> cast(%{decisions: decisions}, [:decisions])
  end

  @doc """
  Changeset for adding a conversation message to the session.
  """
  @spec conversation_changeset(t(), map()) :: Ecto.Changeset.t()
  def conversation_changeset(session, message) do
    conversation = session.conversation ++ [message]

    session
    |> cast(%{conversation: conversation}, [:conversation])
  end

  @doc """
  Changeset for adding an operation to the session.
  """
  @spec operation_changeset(t(), map()) :: Ecto.Changeset.t()
  def operation_changeset(session, operation) do
    operations = session.operations ++ [operation]

    session
    |> cast(%{operations: operations}, [:operations])
  end

  # Validates that state transitions are valid
  defp validate_state_transition(changeset) do
    current = changeset.data.state
    new = get_change(changeset, :state)

    case {current, new} do
      {_, nil} ->
        changeset

      {"active", new} when new in ["landed", "abandoned", "conflicted"] ->
        changeset

      {"conflicted", "active"} ->
        changeset

      {"conflicted", "abandoned"} ->
        changeset

      {current, new} ->
        add_error(changeset, :state, "cannot transition from #{current} to #{new}")
    end
  end
end
