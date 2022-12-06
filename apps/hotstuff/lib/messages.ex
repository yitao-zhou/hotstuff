defmodule PBFT.RequestMessage do
  @moduledoc """
  RequestMessage RPC
  """
  alias __MODULE__


  @enforce_keys [
    :operation,
    :timestamp,
    :client,
    :signature
  ]
  defstruct(
    operation: nil,
    timestamp: nil,
    client: nil,
    signature: nil
  )

  @doc """
  Create a new RequestMessage
  """

  @spec new(
          any(),
          non_neg_integer(),
          atom(),
          any()
        ) ::
          %RequestMessage{
            operation: any(),
            timestamp: non_neg_integer(),
            client: atom(),
            signature: any()
          }
  def new(
          operation,
          timestamp,
          client,
          signature
      ) do
    %RequestMessage{
      operation: operation,
      timestamp: timestamp,
      client: client,
      signature: signature
    }
  end
end

