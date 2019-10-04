defmodule Maestro.Types.Event do
  @moduledoc """
  Events are the key component from which state changes are made and projections
  can be built.

  In order to ensure consistent application of events, they are always retrieved
  in order by sequence number. Additionally, events with conflicting sequence
  numbers will be rejected, and the aggregate can retry the command that
  generated the events that were committed second.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias __MODULE__

  @type sequence :: integer()

  @type aggregate_id :: HLClock.Timestamp.t()

  @type t :: %__MODULE__{
          timestamp: HLClock.Timestamp.t(),
          aggregate_id: aggregate_id(),
          sequence: sequence(),
          type: String.t(),
          body: map()
        }

  # timestamp and sequence are nil since command handlers don't generate HLC's
  # or decide sequence numbers; the database doesn't actually allow these to be
  # nil outside of this particular use case
  @type uncommitted :: %__MODULE__{
          aggregate_id: aggregate_id(),
          type: String.t(),
          body: map(),
          timestamp: nil,
          sequence: nil
        }

  @primary_key false
  schema "event_log" do
    field(:timestamp, EctoHLClock, primary_key: true)
    field(:aggregate_id, EctoHLClock)
    field(:sequence, :integer)
    field(:type, :string)
    field(:body, :map)
  end

  @doc """
  Ensure that events are well formed and that sequence conflicts surface
  properly when attempting to commit them to the log.
  """
  def changeset(%Event{} = e) do
    e
    |> change()
    |> validate_required([:timestamp, :aggregate_id, :sequence, :type, :body])
    |> unique_constraint(
      :sequence,
      name: :aggregate_sequence_index,
      message: "dupe_seq_agg"
    )
  end
end
