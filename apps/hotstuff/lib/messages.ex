defmodule HotStuff.LogEntry do
  @moduledoc """
  Log entry for HotStuff implementation.
  """
  alias __MODULE__
  @enforce_keys [:height, :view_id]
  defstruct(
    height: nil,
    view_id: nil,
    operation: nil,
    requester: nil,
    argument: nil
  )

  @doc """
  Return an empty log entry, this is mostly
  used for convenience.
  """
  @spec empty() :: %LogEntry{height: 0, view_id: 0}
  def empty do
    %LogEntry{height: 0, view_id: 0}
  end

  @doc """
  Return a nop entry for the given height.
  """
  @spec nop(non_neg_integer(), non_neg_integer(), atom()) :: %LogEntry{
          height: non_neg_integer(),
          view_id: non_neg_integer(),
          requester: atom() | pid(),
          operation: :nop,
          argument: none()
        }
  def nop(height, view_id, requester) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :nop,
      argument: nil
    }
  end

  @doc """
  Return a log entry for an `enqueue` operation.
  """
  @spec enqueue(non_neg_integer(), non_neg_integer(), atom(), any()) ::
          %LogEntry{
            height: non_neg_integer(),
            view_id: non_neg_integer(),
            requester: atom() | pid(),
            operation: :enq,
            argument: any()
          }
  def enqueue(height, view_id, requester, item) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :enq,
      argument: item
    }
  end

  @doc """
  Return a log entry for a `dequeue` operation.
  """
  @spec dequeue(non_neg_integer(), non_neg_integer(), atom()) :: %LogEntry{
          height: non_neg_integer(),
          view_id: non_neg_integer(),
          requester: atom() | pid(),
          operation: :enq,
          argument: none()
        }
  def dequeue(height, view_id, requester) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :deq,
      argument: nil
    }
  end
end


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
