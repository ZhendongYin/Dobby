defmodule Dobby.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo
  alias Dobby.Accounts.Admin

  @doc """
  Gets a single admin by email.
  """
  def get_admin_by_email(email) when is_binary(email) do
    Repo.get_by(Admin, email: email)
  end

  @doc """
  Gets a single admin.
  """
  def get_admin!(id), do: Repo.get!(Admin, id)

  @doc """
  Registers an admin.
  """
  def register_admin(attrs \\ %{}) do
    %Admin{}
    |> Admin.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking admin changes.
  """
  def change_admin(%Admin{} = admin, attrs \\ %{}) do
    Admin.changeset(admin, attrs)
  end

  @doc """
  Authenticates an admin by email and password.
  """
  def authenticate_admin(email, password) do
    admin = get_admin_by_email(email)

    cond do
      admin && Bcrypt.verify_pass(password, admin.hashed_password) ->
        {:ok, admin}

      admin ->
        {:error, :invalid_password}

      true ->
        Bcrypt.no_user_verify()
        {:error, :not_found}
    end
  end
end
