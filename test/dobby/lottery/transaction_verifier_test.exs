defmodule Dobby.Lottery.TransactionVerifierTest do
  use Dobby.DataCase

  alias Dobby.{Accounts, Campaigns, Lottery.TransactionVerifier}

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "verifier_admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Verifier Admin #{unique}"
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        "name" => "Verifier Campaign #{unique}",
        "description" => "Description",
        "status" => "active",
        "starts_at" => DateTime.add(now, -3600, :second),
        "ends_at" => DateTime.add(now, 7200, :second),
        "admin_id" => admin.id,
        "enable_protection" => false,
        "protection_count" => 0
      })

    %{campaign: campaign}
  end

  describe "verify/2" do
    test "returns ok with transaction number for valid input", %{campaign: campaign} do
      transaction_number = "TX123456789"

      assert {:ok, result} = TransactionVerifier.verify(transaction_number, campaign)
      assert result.transaction_number == transaction_number
      assert result.campaign_id == campaign.id
    end

    test "returns error when stub_error is configured", %{campaign: campaign} do
      transaction_number = "TX123456789"

      # Set application env to simulate error
      original_env = Application.get_env(:dobby, :transaction_verifier_stub_error)
      Application.put_env(:dobby, :transaction_verifier_stub_error, :service_unavailable)

      try do
        assert {:error, :service_unavailable} =
                 TransactionVerifier.verify(transaction_number, campaign)
      after
        # Restore original env
        if original_env do
          Application.put_env(:dobby, :transaction_verifier_stub_error, original_env)
        else
          Application.delete_env(:dobby, :transaction_verifier_stub_error)
        end
      end
    end

    test "handles different transaction number formats", %{campaign: campaign} do
      test_cases = [
        "TX123",
        "ABC-123-XYZ",
        "1234567890",
        "transaction-number-with-dashes"
      ]

      for tx_num <- test_cases do
        assert {:ok, result} = TransactionVerifier.verify(tx_num, campaign)
        assert result.transaction_number == tx_num
      end
    end
  end
end
