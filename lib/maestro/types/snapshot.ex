defmodule Maestro.Types.Snapshot do
  @moduledoc """
  `Maestro.Aggregate.Root`s can commit state that has been computed from events.

  Roots can commit state that has been computed from the application
  of events. This is useful if events are expensive to apply or if there are a
  sufficiently large number of events that replaying from sequence=1 would be
  impractical.

  With `Maestro.Types.Event`s, `:body` is the necessary information to apply the
  event. In the case of `Snapshot`s, the body is the actual computed state of
  the entity.
  """

  use Ecto.Schema

  @type sequence :: integer()

  @type aggregate_id :: HLClock.Timestamp.t()

  @type t :: %__MODULE__{
          aggregate_id: aggregate_id(),
          sequence: sequence(),
          body: map()
        }

  @primary_key false
  schema "snapshots" do
    field(:aggregate_id, EctoHLClock, primary_key: true)
    field(:sequence, :integer)
    field(:body, :map)
  end
end
