defmodule Maestro.Generators do
  @moduledoc """
  Property testing utilities including:
    * HLC Timestamp generator
  """

  import StreamData
  import ExUnitProperties

  alias HLClock.Timestamp
  alias Maestro.Types.Command

  @max_node_size 18_446_744_073_709_551_615
  @max_counter_size 65_535
  @max_time_size 2_147_483_647

  def timestamp do
    gen all(
          time <- integer(0..max_time()),
          counter <- integer(0..max_counter()),
          node_id <- integer(0..max_node())
        ) do
      Timestamp.new(time, counter, node_id)
    end
  end

  def max_node, do: @max_node_size
  def max_time, do: @max_time_size
  def max_counter, do: @max_counter_size

  def commands(agg_id, opts \\ []) do
    defaults = [max_commands: 10]
    [max_commands: max_commands] = Keyword.merge(defaults, opts)

    gen all(
          com_flags <-
            list_of(
              boolean(),
              max_length: max_commands,
              min_length: 1
            )
        ) do
      com_flags
      |> Enum.map(&to_command(&1, agg_id))
    end
  end

  def to_command(true, agg_id) do
    %Command{
      type: "increment_counter",
      aggregate_id: agg_id,
      data: %{}
    }
  end

  def to_command(false, agg_id) do
    %Command{
      type: "decrement_counter",
      aggregate_id: agg_id,
      data: %{}
    }
  end
end
