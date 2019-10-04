defmodule Mix.Tasks.Maestro.Create.EventStoreMigration do
  @moduledoc """
  Using the work already done in `Mix.Ecto`, generate a migration that creates
  the event_log and snapshot tables with HLC constraints.

  ## Example

      mix maestro.create.event_store_migration --repo MyApp.Repo
      mix maestro.create.event_store_migration -n diff_name_for_migration
  """

  use Mix.Task

  import Mix.Generator,
    only: [
      embed_template: 2,
      create_directory: 1,
      create_file: 2
    ]

  import Mix.Ecto, only: [parse_repo: 1, ensure_repo: 2]

  @change """
      create table(:event_log, primary_key: false) do
        add :timestamp, :binary, null: false, primary_key: true
        add :aggregate_id, :binary, null: false
        add :sequence, :integer, null: false
        add :type, :string, size: 256, null: false
        add :body, :map, null: false
      end

      create table(:snapshots, primary_key: false) do
        add :aggregate_id, :binary, null: false, primary_key: true
        add :sequence, :integer, null: false
        add :body, :map, null: false
      end

      EctoHLClock.Migration.create_hlc_constraint(:event_log, :timestamp)
      EctoHLClock.Migration.create_hlc_constraint(:event_log, :aggregate_id)
      EctoHLClock.Migration.create_hlc_constraint(:snapshots, :aggregate_id)

      create constraint(:event_log, :sequence, check: "sequence > 0")
      create unique_index(:event_log, [:aggregate_id, :sequence],
        name: "aggregate_sequence_index")
  """

  @doc false
  def run(args) do
    [repo | _] = parse_repo(args)
    ensure_repo(repo, args)

    migration_name = parse_migration_name(args)

    file =
      Path.join("priv/repo/migrations/", "#{timestamp()}_#{migration_name}.exs")

    create_directory(Path.dirname(file))

    assigns = [
      mod: Module.concat([repo, Migrations, EventLogAndSnapshots]),
      change: @change
    ]

    create_file(file, migration_template(assigns))
  end

  defp parse_migration_name(args) do
    {parsed, _, _} =
      OptionParser.parse(
        args,
        aliases: [n: :name],
        strict: [name: :string]
      )

    Keyword.get(parsed, :name, "event_log_and_snapshots")
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  embed_template(:migration, """
  defmodule <%= inspect @mod %> do
    use Ecto.Migration

    def change do
  <%= @change %>
    end
  end
  """)
end
