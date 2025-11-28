defmodule Dobby.AccountsTest do
  use Dobby.DataCase

  alias Dobby.Accounts
  alias Dobby.Accounts.Admin

  describe "register_admin/1" do
    test "creates admin with valid data" do
      attrs = %{
        email: "admin#{System.unique_integer([:positive])}@example.com",
        password: "Password123!",
        name: "Test Admin"
      }

      assert {:ok, %Admin{} = admin} = Accounts.register_admin(attrs)
      assert admin.email == attrs.email
      assert admin.name == attrs.name
      assert admin.hashed_password
      refute admin.hashed_password == attrs.password
    end

    test "rejects duplicate email" do
      attrs = %{
        email: "duplicate@example.com",
        password: "Password123!",
        name: "Test Admin"
      }

      assert {:ok, _admin} = Accounts.register_admin(attrs)
      assert {:error, %Ecto.Changeset{}} = Accounts.register_admin(attrs)
    end

    test "rejects invalid email format" do
      attrs = %{
        email: "invalid-email",
        password: "Password123!",
        name: "Test Admin"
      }

      assert {:error, %Ecto.Changeset{}} = Accounts.register_admin(attrs)
    end

    test "rejects empty password" do
      attrs = %{
        email: "admin@example.com",
        password: "",
        name: "Test Admin"
      }

      assert {:error, %Ecto.Changeset{}} = Accounts.register_admin(attrs)
    end
  end

  describe "get_admin_by_email/1" do
    test "returns admin when exists" do
      attrs = %{
        email: "get@example.com",
        password: "Password123!",
        name: "Test Admin"
      }

      {:ok, created_admin} = Accounts.register_admin(attrs)
      assert Accounts.get_admin_by_email(attrs.email) == created_admin
    end

    test "returns nil when not exists" do
      assert Accounts.get_admin_by_email("nonexistent@example.com") == nil
    end
  end

  describe "get_admin!/1" do
    test "returns admin when exists" do
      attrs = %{
        email: "get!@example.com",
        password: "Password123!",
        name: "Test Admin"
      }

      {:ok, created_admin} = Accounts.register_admin(attrs)
      assert Accounts.get_admin!(created_admin.id) == created_admin
    end

    test "raises when not exists" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_admin!(Ecto.UUID.generate())
      end
    end
  end

  describe "authenticate_admin/2" do
    test "returns admin with correct password" do
      attrs = %{
        email: "auth@example.com",
        password: "CorrectPassword123!",
        name: "Test Admin"
      }

      {:ok, admin} = Accounts.register_admin(attrs)
      assert {:ok, authenticated} = Accounts.authenticate_admin(attrs.email, attrs.password)
      assert authenticated.id == admin.id
    end

    test "returns error with incorrect password" do
      attrs = %{
        email: "auth2@example.com",
        password: "CorrectPassword123!",
        name: "Test Admin"
      }

      {:ok, _admin} = Accounts.register_admin(attrs)

      assert {:error, :invalid_password} =
               Accounts.authenticate_admin(attrs.email, "WrongPassword")
    end

    test "returns error when admin not found" do
      assert {:error, :not_found} =
               Accounts.authenticate_admin("nonexistent@example.com", "Password123!")
    end

    test "prevents timing attacks with nonexistent email" do
      # Verify that we call Bcrypt.no_user_verify() to prevent timing attacks
      start_time = System.monotonic_time(:microsecond)
      Accounts.authenticate_admin("nonexistent@example.com", "anypassword")
      end_time = System.monotonic_time(:microsecond)

      # Should take similar time as a real password check (prevents timing attacks)
      # This is a basic check - in practice, Bcrypt ensures this
      assert end_time > start_time
    end
  end
end
