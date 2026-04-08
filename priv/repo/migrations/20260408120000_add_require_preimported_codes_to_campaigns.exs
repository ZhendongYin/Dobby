defmodule Dobby.Repo.Migrations.AddRequirePreimportedCodesToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :require_preimported_codes, :boolean, null: false, default: true
    end
  end
end
