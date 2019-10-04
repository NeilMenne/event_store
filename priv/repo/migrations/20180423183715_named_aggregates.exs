defmodule Maestro.Repo.Migrations.NamedAggregates do
  use Ecto.Migration

  def change do
    create table(:named_aggregates, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, size: 50, null: false)
      add(:aggregate_id, :binary, null: false)
    end

    EctoHLClock.Migration.create_hlc_constraint(
      :named_aggregates,
      :aggregate_id
    )

    create(
      unique_index(
        :named_aggregates,
        [:name],
        name: "unique_aggregate_names_index"
      )
    )
  end
end
