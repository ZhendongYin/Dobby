defmodule Dobby.Lottery.TransactionVerifier do
  @moduledoc """
  Integrates with external services to validate transaction numbers.

  TODO: Replace stub implementation with actual API call.
  """

  require Logger

  @doc """
  Validates the transaction number for the given campaign.

  For now this always returns `{:ok, %{transaction_number: transaction_number}}`.
  """
  @spec verify(String.t(), Dobby.Campaigns.Campaign.t()) ::
          {:ok, map()} | {:error, term()}
  def verify(transaction_number, campaign) when is_binary(transaction_number) do
    Logger.debug(
      "Stub transaction verification for #{transaction_number} in campaign #{campaign.id}"
    )

    # TODO: implement actual HTTP call to external service
    case Application.get_env(:dobby, :transaction_verifier_stub_error) do
      nil ->
        {:ok, %{transaction_number: transaction_number, campaign_id: campaign.id}}

      reason ->
        {:error, reason}
    end
  end
end
