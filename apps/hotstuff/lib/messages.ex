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

defmodule PBFT.ReplyMessage do
  @moduledoc """
  ReplyMessage RPC
  """
  alias __MODULE__


  @enforce_keys [
    :viewID,
    :timestamp,
    :client,
    :replicaID,
    :result,
    :signature
  ]
  defstruct(
    viewID: nil,
    timestamp: nil,
    client: nil,
    replicaID: nil,
    result: nil,
    signature: nil
  )

  @doc """
  Create a new ReplyMessage
  """

  @spec new(
          non_neg_integer(),
          non_neg_integer(),
          atom(),
          atom(),
          any(),
          any()
        ) ::
          %ReplyMessage{
            viewID: non_neg_integer(),
            timestamp: non_neg_integer(),
            client: atom(),
            replicaID: atom(),
            result: any(),
            signature: any()
          }
  def new(
          viewID,
          timestamp,
          client,
          replicaID,
          result,
          signature
      ) do
    %ReplyMessage{
      viewID: viewID,
      timestamp: timestamp,
      client: client,
      replicaID: replicaID,
      result: result,
      signature: signature
    }
  end
end


defmodule PBFT.PrePrepareMessage do
  @moduledoc """
  PrePrepareMessage RPC
  """
  alias __MODULE__


  @enforce_keys [
    :viewID,
    :sequenceNumber,
    :digest,
    :signature,
    :message
  ]
  defstruct(
    viewID: nil,
    sequenceNumber: nil,
    digest: nil,
    signature: nil,
    message: nil
  )

  @doc """
  Create a new PrePrepareMessage
  """

  @spec new(
          non_neg_integer(),
          non_neg_integer(),
          any(),
          any(),
          any()
        ) ::
          %PrePrepareMessage{
            viewID: non_neg_integer(),
            sequenceNumber: non_neg_integer(),
            digest: any(),
            signature: any(),
            message: any()
          }
  def new(
          viewID,
          sequenceNumber,
          digest,
          signature,
          message
      ) do
    %PrePrepareMessage{
      viewID: viewID,
      sequenceNumber: sequenceNumber,
      digest: digest,
      signature: signature,
      message: message
    }
  end
end

defmodule PBFT.PrepareMessage do
  @moduledoc """
  PrepareMessage RPC
  """
  alias __MODULE__


  @enforce_keys [
    :viewID,
    :sequenceNumber,
    :digest,
    :backupID,
    :signature
  ]
  defstruct(
    viewID: nil,
    sequenceNumber: nil,
    digest: nil,
    backupID: nil,
    signature: nil
  )

  @doc """
  Create a new PrepareMessage
  """

  @spec new(
          non_neg_integer(),
          non_neg_integer(),
          any(),
          atom(),
          any()
        ) ::
          %PrepareMessage{
            viewID: non_neg_integer(),
            sequenceNumber: non_neg_integer(),
            digest: any(),
            backupID: atom(),
            signature: any()
          }
  def new(
          viewID,
          sequenceNumber,
          digest,
          backupID,
          signature
      ) do
    %PrepareMessage{
      viewID: viewID,
      sequenceNumber: sequenceNumber,
      digest: digest,
      backupID: backupID,
      signature: signature
    }
  end
end

defmodule PBFT.CommitMessage do
  @moduledoc """
  CommitMessage RPC
  """
  alias __MODULE__


  @enforce_keys [
    :viewID,
    :sequenceNumber,
    :digest,
    :replicaID,
    :signature
  ]
  defstruct(
    viewID: nil,
    sequenceNumber: nil,
    digest: nil,
    replicaID: nil,
    signature: nil
  )

  @doc """
  Create a new CommitMessage
  """

  @spec new(
          non_neg_integer(),
          non_neg_integer(),
          any(),
          atom(),
          any()
        ) ::
          %CommitMessage{
            viewID: non_neg_integer(),
            sequenceNumber: non_neg_integer(),
            digest: any(),
            replicaID: atom(),
            signature: any()
          }
  def new(
          viewID,
          sequenceNumber,
          digest,
          replicaID,
          signature
      ) do
    %CommitMessage{
      viewID: viewID,
      sequenceNumber: sequenceNumber,
      digest: digest,
      replicaID: replicaID,
      signature: signature
    }
  end
end

