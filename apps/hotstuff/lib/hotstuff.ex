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
    replica_table: nil,

    curr_view: nil,
    current_leader: nil,
    is_leader: nil,

    #Log is the highest tree branch kown to the replica, and we save the brach as a list
    #with latter entries (lower node in the tree) closer to the head of the list
    log: nil,

    prepared_qc: nil,
    #The highest qc (index the replica voted commit)
    locked_qc: nil,
    #highest qc which a replica voted pre-commit
    prepare_qc: nil,

    node_to_propose: nil,

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
      curr_view: 1,
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

  # Utility function to send a message to all
  # processes other than the caller. Should only be used by leader.
  @spec broadcast_to_others(%HotStuff{is_leader: true}, any()) :: [boolean()]
  defp broadcast_to_others(state, message) do
    me = whoami()

    state.view
    |> Enum.filter(fn pid -> pid != me end)
    |> Enum.map(fn pid -> send(pid, message) end)
  end

  @doc """
  Add log entries to the log. This adds entries to the beginning
  of the log, we assume that entries are already correctly ordered
  (see structural note about log above.).
  """
  @spec add_log_entries(%HotStuff{}, [%HotStuff.LogEntry{}]) :: %HotStuff{}
  def add_log_entries(state, entries) do
    %{state | log: entries ++ state.log}
  end

  @doc """
  Get index for the last log entry.
  """
  @spec get_last_log_height(%HotStuff{}) :: non_neg_integer()
  def get_last_log_height(state) do
    Enum.at(state.log, 0, HotStuff.LogEntry.empty()).height
  end

  @doc """
  This function is to generate a Msg given state, type, node, qc
  """
  @spec generate_msg(any(), any(), any(), any()) :: any()
  def generate_msg(state, type, node, qc) do
    HotStuff.Msg.new(type, state.curr_view, node, qc)
  end

  @doc """
  This function is to generate a VoteMsg given state, type, node, qc
  """
  @spec generate_votemsg(any(), any(), any(), any()) :: any()
  def generate_votemsg(state, type, node, qc) do
    msg = generate_msg(state, type, node, qc)
    # TODO: partial signature, replaced with a number right now instead
    partialSig = 1

    HotStuff.VoteMsg.new(msg, partialSig)
  end

  @doc """
  This function is to create a leaf
  """
  @spec create_leaf(%HotStuff.QC{}, %HotStuff.LogEntry{}) :: %HotStuff.LogEntry{}
  def createLeaf(high_qc, proposal_node) do
    %{proposal_node | parent: high_qc.node}
  end

  @doc """
  This function is to generate QC
  """
  @spec create_quorum_cert(%HotStuff.Msg{}, any()) :: any()
  def create_quorum_cert(message, partial_sigs) do
    # TODO: need to consider how to combine partial sigatures

    # sig needs to be changed
    sig = 1
    HotStuff.QC.new(message.type, message.viewNumber, message.node, sig)
  end

  @doc """
  This function is to check matching msg
  """
  @spec matching_Msg(atom(), non_neg_integer(), atom(), non_neg_integer()) :: boolean()
  def matching_Msg(message_type, message_view, type, view) do
    message_type == type and message_view == view
  end

  @doc """
  This function is to check matching qc
  """
  @spec matching_qc(any(), any(), any()) :: boolean()
  def matching_qc(qc, type, view) do
    qc.type == type and qc.viewNumber == view
  end

  @doc """
  This function is to check matching qc
  """
  @spec safeNode(any(), any()) :: boolean()
  def safeNode(node, qc) do
    raise "Not Yet Implemented"
  end

  @spec get_majority(%HotStuff{}, any()) :: boolean()
  def getMajority(state, extra_state) do
    length(extra_state.collector) > Integer.floor_div(length(state.replica_table), 3) * 2
  end

  @doc """
  This function transitions a process so it is a primary.
  """
  @spec become_leader(%HotStuff{}) :: no_return()
  def become_leader(state) do
    Logger.info("Process #{inspect(whoami())} become leader in view #{inspect(state.curr_view)}")
    state = %{state | is_leader: true}
    leader(state, %{type: :new_view, collector: [state.prepared_qc]})
  end

  @doc """
  This function implements the state machine for a process
  that is currently a primary.
  """
  @spec leader(%HotStuff{is_leader: true}, any()) :: no_return()
  #Use the `extra_state` to track the phase leader is in
  #and the number of different type of qc it have received in given phase
  def leader(state, extra_state) do
    receive do
      {sender,
      %HotStuff.Msg{
        type: type
        view_number: view_number,
        node: log_entry,
        justify: qc
      }} ->
        #Tracking :new_view message received from followers and put them into the collector
        if (matching_Msg(type, view_number, extra_state.type, state.curr_view-1)) do
          %{extra_state | collector: qc ++ extra_state.collector}
          #Wait for (n-f-1) = 2f :new_view message from the followers
          if get_majority(state, extra_state) do
            high_qc =
              extra_state.collector
              |> Enum.max_by(fn x->x.view_number end)
            #Create the node to be proposed by extending from the high_qc node
            node_proposal = create_leaf(high_qc, node_to_propose)
            #create the prepare message and broadcast to all the follwers
            prepare_msg = generate_msg(state, :prepare, node_proposal, high_qc)
            broadcast_to_others(state, prepare_msg)
            #The leader enters the prepare phase after the broadcast
            extra_state = %{extra_state | type: :prepare, collector: []}
          end
        else
          Logger.info("leader #{inspect(whoami())} receive unexpected message")
        end
        leader(state, extra_state)

        {sender,
        %HotStuff.VoteMsg{
          message: message,
          partial_sig: partial_sig
        }} ->
          #For each phase, collect the partial sig received from follower
          if (matching_Msg(message.type, message.view_number, extra_state.type, state.curr_view)) do
            %{extra_state | collector: partial_sig ++ extra_state.collector}
            #Wait for (n-f) votes
            if get_majority(state, extra_state) do
              #combine the partial signature through threshold signature
              state.prepared_qc = create_quorum_cert(message, extra_state.collector)
              next_type =
                case extra_state.type do
                  :prepare ->
                    :precommit
                  :precommit ->
                    :commit
                  :commit ->
                    :decide
                end
              msg = generate_msg(state, next_type, nil, state.prepared_qc)
              broadcast_to_others(state, msg)
              #Leader go into next phase
              extra_state = %{extra_state | type: next_type, collector: []}
            end
          end
          leader(state, extra_state)

        #Message received from client
        {sender, :nop} ->
          Logger.info("Leader #{whoami} receive client nop request")

    end
  end

  @doc """
  This function makes a replica as backup
  """
  @spec become_replica(%HotStuff{is_leader: false}) :: no_return()
  def become_replica(state) do
    raise "Not yet implemented"
  end

  @doc """

  """
  @spec replica(%HotStuff{is_leader: false}, any()) :: no_return()
  def replica(state, extra_state) do
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
  @enforce_keys [:leaderID]
  defstruct(leaderID: nil)

  @doc """
  Construct a new PBFT Client.
  """
  @spec new_client(atom()) :: %Client{leaderID: atom()}
  def new_client(member) do
    %Client{leaderID: member}
  end

  @doc """
  Send a nop request to the RSM.
  """
  @spec nop(%Client{}) :: {:ok, %Client{}}
  def nop(client) do
    leader = client.leaderID
    send(leader, :nop)

    receive do
      # {_, {:redirect, new_leader}} ->
      #   nop(%{client | leader: new_leader})

      {_, :ok} ->
        {:ok, client}
    end
  end
end
