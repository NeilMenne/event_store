defmodule Maestro.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {HLClock, name: :maestro_hlc},
      {Registry, keys: :unique, name: Maestro.Aggregate.Registry},
      {Maestro.Aggregate.Supervisor, []}
    ]

    opts = [strategy: :one_for_all, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
