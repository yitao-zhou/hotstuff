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

<<<<<<< HEAD
=======
defmodule HotStuff.Msg do
  @moduledoc """
  Utility 1 function Msg
>>>>>>> 7d1fbcd00748013875132861272821c499e96193
  """
  alias __MODULE__

  @enforce_keys [
    :type, :viewNumber, :node, :justify
  ]
  defstruct(
    type: nil, viewNumber: nil, node: nil, justify: nil
  )

  @doc """
  Create a new Msg
  """

  @spec new(
          any(),
          non_neg_integer(),
          atom(),
          any()
        ) ::
          %Msg{
            type: any(),
            viewNumber: non_neg_integer(),
            node: atom(),
            justify: any()
          }
  def new(
      type,
      viewNumber,
      node,
      justify
      ) do
    %Msg{
      type: type,
      viewNumber: viewNumber,
      node: node,
      justify: justify
    }
  end
end

<<<<<<< HEAD
=======
defmodule HotStuff.VoteMsg do
  @moduledoc """
  Utility 2 function VoteMsg
  """
  alias __MODULE__

  # @enforce_keys [

  # ]
  defstruct(
    message: nil, partialSig: nil
  )

  @doc """
  Create a new Msg
  """

  @spec new(
          any(),
          any()
        ) ::
          %VoteMsg{
            message: any(),
            partialSig: any()
          }
  def new(
      message,
      partialSig
      ) do
    %VoteMsg{
      message: message,
      partialSig: partialSig
    }
  end
end

defmodule HotStuff.QC do
  @moduledoc """
  quorum certificate
  """
  alias __MODULE__

  # @enforce_keys [

  # ]
  defstruct(
    type: nil, viewNumber: nil, node: nil, sig: nil
  )

  @doc """
  Create a new Msg
  """

  @spec new(
          any(),
          any(),
          any(),
          any()
        ) ::
          %QC{
            type: any(),
            viewNumber: any(),
            node: any(),
            sig: any()
          }
  def new(
      type,
      viewNumber,
      node,
      sig
      ) do
    %QC{
      type: type,
      viewNumber: viewNumber,
      node: node,
      sig: sig
    }
  end
end

>>>>>>> 7d1fbcd00748013875132861272821c499e96193
