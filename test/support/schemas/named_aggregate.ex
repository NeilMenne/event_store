defmodule Maestro.Schemas.NamedAggregate do
  @moduledoc """
  A simple DB schema that will be used to provide a working example/test case
  for strong consistency w.r.t. projections.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "named_aggregates" do
    field(:name, :string)
    field(:aggregate_id, EctoHLClock)
  end
end
