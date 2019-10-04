defmodule Maestro.Repo.Migrations.EventLogAndSnapshots do
  use Ecto.Migration

  def change do
    create table(:event_log, primary_key: false) do
      add :timestamp, :binary, null: false, primary_key: true
      add :aggregate_id, :binary, null: false
      add :sequence, :integer, null: false
      add :type, :string, size: 256, null: false
      add :body, :map, null: false
    end

    EctoHLClock.Migration.create_hlc_constraint(:event_log, :timestamp)
    EctoHLClock.Migration.create_hlc_constraint(:event_log, :aggregate_id)

    create constraint(:event_log, :sequence, check: "sequence > 0")
    create unique_index(:event_log, [:aggregate_id, :sequence],
      name: "aggregate_sequence_index")

    create table(:snapshots, primary_key: false) do
      add :aggregate_id, :binary, null: false, primary_key: true
      add :sequence, :integer, null: false
      add :body, :map, null: false
    end

    EctoHLClock.Migration.create_hlc_constraint(:snapshots, :aggregate_id)
  end
end
