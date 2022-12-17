defmodule HotStuff do
  @moduledoc """
  An implementation of the HotStuff.
  """
  import Emulation, only: [send: 2, timer: 1, now: 0, whoami: 0]

  import Kernel,
    except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

  require Fuzzers

  require Logger

  # This structure contains all the process state
  # required by the HotStuff protocol.
  defstruct(
    #The list of current processes
    replica_table: nil

    view_id: nil,
    current_leader: nil,
    is_leader: nil,

    #Log is the highest tree branch kown to the replica, and we save the brach as a list
    #with latter entries (lower node in the tree) closer to the head of the list
    log: nil,

    commit_height: nil,
    last_applied_height: nil,

    #In this simulation the RSM we are building is a queue
    queue: nil
  )

  @doc """
  Create state for an initial HotStuff cluster.
  Each process should get an appropriately updated version
  of this state.
  """
  @spec new_configuration(
          [atom()],
          non_neg_integer()
        ) :: %HotStuff{}
  def new_configuration(
        replica_table,
        leader
      ) do
    %HotStuff{
      replica_table: replica_table,
      view_id: 0,
      current_leader: leader,
      is_leader: false,
      log: [],
      commit_height: 0,
      last_applied_height: 0,
      queue: :queue.new()
    }
  end

  # Enqueue an item, this **modifies** the state
  # machine, and should only be called when a log
  # entry is committed.
  @spec enqueue(%HotStuff{}, any()) :: %HotStuff{}
  defp enqueue(state, item) do
    %{state | queue: :queue.in(item, state.queue)}
  end

  # Dequeue an item, modifying the state machine.
  # This function should only be called once a
  # log entry has been committed.
  @spec dequeue(%HotStuff{}) :: {:empty | {:value, any()}, %HotStuff{}}
  defp dequeue(state) do
    {ret, queue} = :queue.out(state.queue)
    {ret, %{state | queue: queue}}
  end

  @doc """
  Commit a log entry, advancing the state machine. This
  function returns a tuple:
  * The first element is {requester, return value}.
    Ensure that the leader who committed the log entry sends the return value to the requester.
  * The second element is the updated state.
  """
  @spec commit_log_entry(%HotStuff{}, %HotStuff.LogEntry{}) ::
          {{atom() | pid(), :ok | :empty | {:value, any()}}, %HotStuff{}}
  def commit_log_entry(state, entry) do
    case entry do
      %HotStuff.LogEntry{operation: :nop, requester: r, height: i} ->
        {{r, :ok}, %{state | commit_height: i}}

      %HotStuff.LogEntry{operation: :enq, requester: r, argument: e, height: i} ->
        {{r, :ok}, %{enqueue(state, e) | commit_height: i}}

      %HotStuff.LogEntry{operation: :deq, requester: r, height: i} ->
        {ret, state} = dequeue(state)
        {{r, ret}, %{state | commit_height: i}}

      %HotStuff.LogEntry{} ->
        raise "Log entry with an unknown operation: maybe an empty entry?"

      _ ->
        raise "Attempted to commit something that is not a log entry."
    end
  end


  @doc """
  This function transitions a process so it is a primary.
  """
  @spec become_leader(%HotStuff{}) :: no_return()
  def become_leader(state) do
    Logger.info("Process #{inspect(whoami())} become leader")
    state = %{state | is_leader: true}
  end

  @doc """
  This function implements the state machine for a process
  that is currently a primary.
  """
  @spec leader(%HotStuff{is_leader: true}, any()) :: no_return()
  def leader(state, extra_state) do
    receive do
      {sender, :nop} ->
        send(sender, :ok)
    end
  end

  @doc """
  This function makes a replica as backup
  """
  @spec become_backup(%PBFT{is_primary: false}) :: no_return()
  def become_backup(state) do
    raise "Not yet implemented"
  end

  @doc """

  """
  @spec backup(%PBFT{is_primary: false}, any()) :: no_return()
  def backup(state, extra_state) do
    receive do
      {sender, :nop} ->
        send(sender, :ok)
    end
  end
end

defmodule HotStuff.Client do
  import Emulation, only: [send: 2]

  import Kernel,
    except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

  @moduledoc """
  A client that can be used to connect and send
  requests to the RSM.
  """
  alias __MODULE__
  @enforce_keys [:primaryID]
  defstruct(primaryID: nil)

  @doc """
  Construct a new PBFT Client.
  """
  @spec new_client(atom()) :: %Client{primaryID: atom()}
  def new_client(member) do
    %Client{primaryID: member}
  end

  @doc """
  Send a nop request to the RSM.
  """
  @spec nop(%Client{}) :: {:ok, %Client{}}
  def nop(client) do
    primary = client.primaryID
    send(primary, :nop)

    receive do
      # {_, {:redirect, new_leader}} ->
      #   nop(%{client | leader: new_leader})

      {_, :ok} ->
        {:ok, client}
    end
  end
end
