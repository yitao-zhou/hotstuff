defmodule HotStuff.LogEntry do
  @moduledoc """
  Log entry for HotStuff implementation.
  """
  alias __MODULE__
  @enforce_keys [:height, :view_id, :parent]
  defstruct(
    height: nil,
    view_id: nil,
    operation: nil,
    requester: nil,
    argument: nil,
    parent: nil
  )

  @doc """
  Return an empty log entry, this is mostly
  used for convenience.
  """
  @spec empty() :: %LogEntry{height: 0, view_id: 0, parent: nil}
  def empty do
    %LogEntry{height: 0, view_id: 0, parent: nil}
  end

  @doc """
  Return a nop entry for the given height.
  """
  @spec nop(non_neg_integer(), non_neg_integer(), atom(), non_neg_integer()) :: %LogEntry{
          height: non_neg_integer(),
          view_id: non_neg_integer(),
          requester: atom() | pid(),
          operation: :nop,
          argument: none(),
          parent: non_neg_integer()
        }
  def nop(height, view_id, requester, parent) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :nop,
      argument: nil,
      parent: parent
    }
  end

  @doc """
  Return a log entry for an `enqueue` operation.
  """
  @spec enqueue(non_neg_integer(), non_neg_integer(), atom(), any(), non_neg_integer()) ::
          %LogEntry{
            height: non_neg_integer(),
            view_id: non_neg_integer(),
            requester: atom() | pid(),
            operation: :enq,
            argument: any(),
            parent: non_neg_integer()
          }
  def enqueue(height, view_id, requester, item, parent) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :enq,
      argument: item,
      parent: parent
    }
  end

  @doc """
  Return a log entry for a `dequeue` operation.
  """
  @spec dequeue(non_neg_integer(), non_neg_integer(), atom(), non_neg_integer()) :: %LogEntry{
          height: non_neg_integer(),
          view_id: non_neg_integer(),
          requester: atom() | pid(),
          operation: :enq,
          argument: none(),
          parent: non_neg_integer()
        }
  def dequeue(height, view_id, requester, parent) do
    %LogEntry{
      height: height,
      view_id: view_id,
      requester: requester,
      operation: :deq,
      argument: nil,
      parent: parent
    }
  end
end

defmodule HotStuff.RequestMessage do
  @moduledoc """
  RequestMessage sent by client to the replicas
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

#Define the data structure used in HotStuff
defmodule HotStuff.qc do
  defstruct[:type, :view_id, :branch_height, :sig]
end



defmodule HotStuff.NewViewMessage do
  @moduledoc """
  Sent by a replica when it transition into new view_id and carries the highest prepared_qc received by the replica
  """
  alias HotStuff.NewViewMessage
  alias __MODULE__
  @enforce_keys[
    :view_id,
    :prepared_qc
  ]
  defstruct(
    view_id: nil,
    #prepared_qc is the highest block index of the given replica
    prepared_qc: nil
  )

  @spec new(non_neg_integer(), %HotStuff.qc{}) ::
    %NewViewMessage{
      view_id: non_neg_integer(),
      prepared_qc: non_neg_integer()
    }
    def new(view_id, prepared_qc) do
      %NewViewMessage{
        view_id: view_id,
        prepared_qc: prepared_qc
      }
    end
end
