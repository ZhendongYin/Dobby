defmodule Dobby.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def change do
    create table(:admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :name, :string
      add :role, :string, default: "admin", null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:email])
    create index(:admins, [:role])
  end
end
