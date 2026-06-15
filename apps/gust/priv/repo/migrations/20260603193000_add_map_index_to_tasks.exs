defmodule Gust.Repo.Migrations.AddMapIndexToTasks do
  use Ecto.Migration

  def change do
    alter table(:gust_tasks) do
      add :map_index, :integer
    end

    create unique_index(:gust_tasks, [:run_id, :name],
             where: "map_index IS NULL",
             name: :gust_tasks_run_id_name_unmapped_index
           )

    create unique_index(:gust_tasks, [:run_id, :name, :map_index],
             where: "map_index IS NOT NULL",
             name: :gust_tasks_run_id_name_map_index_mapped_index
           )
  end
end
