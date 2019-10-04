defmodule Maestro.InMemoryTest do
  use ExUnit.Case, async: false
  import StreamData
  import ExUnitProperties
  import Maestro.Generators

  alias Maestro.Store
  alias Maestro.Store.InMemory
  alias Maestro.Types.{Event, Snapshot}

  setup_all do
    Application.put_env(
      :maestro,
      :storage_adapter,
      Maestro.Store.InMemory
    )

    {:ok, pid} = InMemory.start_link()

    on_exit(fn ->
      Process.exit(pid, :normal)
    end)

    :ok
  end

  describe "commit_events/1" do
    property "no conflict events are committed" do
      check all(
              agg_id <- timestamp(),
              times <-
                uniq_list_of(
                  timestamp(),
                  min_length: 1,
                  max_length: 10
                )
            ) do
        InMemory.reset()

        times
        |> Enum.with_index(1)
        |> Enum.map(&to_event(&1, agg_id))
        |> Store.commit_events()

        events = Store.get_events(agg_id, 0)

        assert Enum.count(times) == Enum.count(events)
      end
    end

    property "sequence conflicts are marked for retry" do
      check all(
              agg_id <- timestamp(),
              ts0 <- timestamp(),
              times <- uniq_list_of(timestamp(), min_length: 1)
            ) do
        InMemory.reset()

        times
        |> Enum.with_index(1)
        |> Enum.map(&to_event(&1, agg_id))
        |> Store.commit_events()

        e = to_event({ts0, 1}, agg_id)

        {:error, reason} =
          e
          |> List.wrap()
          |> Store.commit_events()

        assert reason == :retry_command
      end
    end
  end

  describe "get_events/2" do
    property "returns empty list when no relevant events exist" do
      check all(
              agg_id <- timestamp(),
              times <- uniq_list_of(timestamp())
            ) do
        InMemory.reset()

        times
        |> Enum.with_index(1)
        |> Enum.map(&to_event(&1, agg_id))
        |> Store.commit_events()

        assert [] == Store.get_events(agg_id, Enum.count(times) + 1)
      end
    end

    property "returns events otherwise" do
      check all(
              agg_id <- timestamp(),
              times <- uniq_list_of(timestamp(), min_length: 1)
            ) do
        InMemory.reset()

        total = Enum.count(times)

        times
        |> Enum.with_index(1)
        |> Enum.map(&to_event(&1, agg_id))
        |> Store.commit_events()

        seq =
          times
          |> Enum.with_index(1)
          |> Enum.random()
          |> elem(1)

        assert agg_id
               |> Store.get_events(seq)
               |> Enum.count() == total - seq
      end
    end
  end

  describe "commit_snapshot/1" do
    property "commits if newer" do
      check all(
              agg_id <- timestamp(),
              [seq0, seq1] <- uniq_list_of(integer(1..100_000), length: 2)
            ) do
        InMemory.reset()

        agg_id
        |> to_snapshot(seq0, %{"seq" => seq0})
        |> Store.commit_snapshot()

        agg_id
        |> to_snapshot(seq1, %{"seq" => seq1})
        |> Store.commit_snapshot()

        snapshot = Store.get_snapshot(agg_id, 0)
        assert Map.get(snapshot.body, "seq") == max(seq0, seq1)
      end
    end
  end

  describe "get_snapshot/2" do
    property "retrieve if newer" do
      check all(
              agg_id <- timestamp(),
              [seq0, seq1] <- uniq_list_of(integer(1..100_000), length: 2)
            ) do
        InMemory.reset()

        agg_id
        |> to_snapshot(seq0, %{"seq" => seq0})
        |> Store.commit_snapshot()

        case Store.get_snapshot(agg_id, seq1) do
          nil ->
            assert seq1 > seq0

          %Snapshot{} ->
            assert seq1 < seq0
        end
      end
    end
  end

  def to_snapshot(agg_id, seq, body \\ %{}),
    do: %Snapshot{
      aggregate_id: agg_id,
      sequence: seq,
      body: body
    }

  def to_event({ts, seq}, agg_id, body \\ %{}),
    do: %Event{
      timestamp: ts,
      aggregate_id: agg_id,
      sequence: seq,
      body: body
    }
end
