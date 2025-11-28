defmodule Dobby.Accounts.Admin do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "admins" do
    field :email, :string
    field :hashed_password, :string
    field :name, :string
    field :role, :string, default: "admin"
    field :password, :string, virtual: true, redact: true

    has_many :campaigns, Dobby.Campaigns.Campaign

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
  end

  @doc false
  def registration_changeset(admin, attrs, opts \\ []) do
    admin
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_password(opts)
    |> maybe_hash_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_validate_password_format(opts)
  end

  defp maybe_validate_password_format(changeset, opts) do
    if Keyword.get(opts, :validate_password_format, true) do
      changeset
      |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
      |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
      |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/,
        message: "at least one digit or punctuation character"
      )
    else
      changeset
    end
  end

  defp maybe_hash_password(changeset, opts) do
    password = get_change(changeset, :password)

    if password && Keyword.get(opts, :hash_password, true) do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
