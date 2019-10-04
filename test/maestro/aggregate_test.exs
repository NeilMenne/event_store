defmodule Maestro.AggregateTest do
  use ExUnit.Case

  import Ecto.Query
  import ExUnitProperties
  import Maestro.Generators
  import Mock

  alias DBConnection.ConnectionError
  alias Ecto.Adapters.SQL.Sandbox
  alias Maestro.Aggregate.Root
  alias Maestro.{InvalidCommandError, InvalidHandlerError}
  alias Maestro.{Repo, SampleAggregate}
  alias Maestro.Types.{Command, Event}

  setup_all do
    Application.put_env(
      :maestro,
      :storage_adapter,
      Maestro.Store.Postgres
    )

    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "command/event lifecycle" do
    property "commands and events without snapshots" do
      check all(
              agg_id <- timestamp(),
              coms <- commands(agg_id, max_commands: 200)
            ) do
        for com <- coms do
          :ok = SampleAggregate.evaluate(com)
        end

        {:ok, %{"value" => value}} = SampleAggregate.get(agg_id)
        assert value == increments(coms) - decrements(coms)

        {:ok, %{"value" => value}} = SampleAggregate.fetch(agg_id)
        assert value == increments(coms) - decrements(coms)
      end
    end

    test "commands, events, and snapshots" do
      {:ok, agg_id} = SampleAggregate.new()

      {:ok, %{"value" => value}} = SampleAggregate.get(agg_id)
      assert value == 0

      SampleAggregate.evaluate(%Command{
        type: "increment_counter",
        aggregate_id: agg_id,
        data: %{}
      })

      SampleAggregate.evaluate(%Command{
        type: "increment_counter",
        aggregate_id: agg_id,
        data: %{}
      })

      SampleAggregate.snapshot(agg_id)

      agg_id |> Root.whereis(SampleAggregate) |> GenServer.stop()

      {:ok, _pid} = SampleAggregate.start_link(agg_id)

      SampleAggregate.evaluate(%Command{
        type: "increment_counter",
        aggregate_id: agg_id,
        data: %{}
      })

      {:ok, %{"value" => value}} = SampleAggregate.get(agg_id)
      assert value == 3
    end

    test "recover an intermediate state" do
      {:ok, agg_id} = SampleAggregate.new()

      base_command = %Command{
        type: "increment_counter",
        aggregate_id: agg_id,
        data: %{}
      }

      commands = repeat(base_command, 10)

      for com <- commands do
        res = SampleAggregate.evaluate(com)

        case res do
          :ok -> :ok
          {:error, err, stack} -> reraise err, stack
        end
      end

      {:ok, %{"value" => value}} = SampleAggregate.replay(agg_id, 2)
      assert value == 2
      {:ok, %{"value" => current}} = SampleAggregate.get(agg_id)
      assert current == 10
    end
  end

  describe "communicating/handling failure" do
    test "invalid command" do
      {:ok, agg_id} = SampleAggregate.new()

      com = %Command{
        type: "invalid",
        aggregate_id: agg_id,
        data: %{}
      }

      {:error, err, _stack} = SampleAggregate.evaluate(com)

      assert err == InvalidHandlerError.exception(type: "invalid")

      assert_raise(ArgumentError, fn ->
        SampleAggregate.evaluate(%{
          type: "increment_counter",
          data: %{}
        })
      end)
    end

    test "handler rejected command" do
      {:ok, agg_id} = SampleAggregate.new()

      com = %Command{
        type: "conditional_increment",
        aggregate_id: agg_id,
        data: %{"do_inc" => false}
      }

      {:error, err, _stack} = SampleAggregate.evaluate(com)

      assert err ==
               InvalidCommandError.exception(
                 message: "command incorrectly specified"
               )
    end

    test "handler raised an unexpected error" do
      {:ok, agg_id} = SampleAggregate.new()

      com = %Command{
        type: "raise_command",
        aggregate_id: agg_id,
        data: %{"raise" => true}
      }

      {:error, err, _stack} = SampleAggregate.evaluate(com)

      assert err ==
               ArgumentError.exception(
                 message: "commands can raise arbitrary exceptions as well"
               )
    end

    test "store error" do
      {:ok, agg_id} = SampleAggregate.new()

      com = %Command{
        type: "increment_counter",
        aggregate_id: agg_id,
        data: %{}
      }

      with_mock Maestro.Store,
        max_sequence: fn -> 2_147_483_647 end,
        get_snapshot: fn _, _, _ ->
          raise(ConnectionError, "some")
        end do
        {:error, err, _stack} = SampleAggregate.evaluate(com)
        assert err == ConnectionError.exception("some")
      end
    end
  end

  test "event_type/2" do
    assert Root.event_type(Maestro.SampleAggregate.Events, %{
             __struct__: Maestro.SampleAggregate.Events.TypedEvent.Completed
           }) == "typed_event.completed"
  end

  describe "projections" do
    test "strong projections are invoked/called" do
      {:ok, agg_id} = SampleAggregate.new()

      com = %Command{
        type: "name_counter",
        aggregate_id: agg_id,
        data: %{"name" => "sample"}
      }

      :ok = SampleAggregate.evaluate(com)

      {:error, err, _stack} = SampleAggregate.evaluate(com)

      assert err ==
               InvalidCommandError.exception(
                 message: "altering names is prohibited"
               )

      {:ok, agg_id_2} = SampleAggregate.new()

      com_2 = Map.put(com, :aggregate_id, agg_id_2)

      {:error, err, _stack} = SampleAggregate.evaluate(com_2)

      assert err.__struct__ == Ecto.ConstraintError

      # no events were committed
      assert Repo.one(
               from(
                 e in Event,
                 where: e.aggregate_id == ^agg_id_2,
                 select: count(e.timestamp)
               )
             ) == 0
    end
  end

  def repeat(val, times) do
    Enum.map(0..(times - 1), fn _ -> val end)
  end

  def increments(commands) do
    commands
    |> Enum.filter(&is_increment/1)
    |> Enum.count()
  end

  def decrements(commands) do
    commands
    |> Enum.filter(&is_decrement/1)
    |> Enum.count()
  end

  defp is_increment(%{type: t}), do: t == "increment_counter"

  defp is_decrement(%{type: t}), do: t == "decrement_counter"
end
