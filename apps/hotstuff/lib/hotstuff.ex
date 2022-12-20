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
    # The list of current processes
    replica_table: nil,
    curr_view: nil,
    current_leader: nil,
    is_leader: nil,

    # Log is the highest tree branch kown to the replica, and we save the brach as a list
    # with latter entries (lower node in the tree) closer to the head of the list
    log: nil,

    # highest qc which a replica voted pre-commit
    prepared_qc: nil,
    precommit_qc: nil,
    commit_qc: nil,
    # The highest qc (index the replica voted commit)
    locked_qc: nil,
    node_to_propose: nil,
    commit_height: nil,
    last_applied_height: nil,
    # In this simulation the RSM we are building is a queue
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
      curr_view: 0,
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
      %HotStuff.LogEntry{operation: :nop, requester: r} ->
        {{r, :ok}, state}

      %HotStuff.LogEntry{operation: :enq, requester: r, argument: e} ->
        {{r, :ok}, enqueue(state, e)}

      %HotStuff.LogEntry{operation: :deq, requester: r} ->
        {ret, state} = dequeue(state)
        {{r, ret}, state}

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

    state.replica_table
    |> Enum.filter(fn pid -> pid != me end)
    |> Enum.map(fn pid -> send(pid, message) end)
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
  def create_leaf(high_qc, proposal_node) do
    # Hash the parent node and assign hash value to the new log entry
    %{proposal_node | parent: :crypto.hash(:sha256, high_qc.node)}
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
  @spec matching_msg(atom(), non_neg_integer(), atom(), non_neg_integer()) :: boolean()
  def matching_msg(message_type, message_view, type, view) do
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
  @spec safeNode(%HotStuff{}, any(), any()) :: boolean()
  def safeNode(state, node, qc) do
    raise "Not Yet Implemented"
  end

  @spec get_majority(%HotStuff{}, any()) :: boolean()
  def get_majority(state, extra_state) do
    length(extra_state.collector) > Integer.floor_div(length(state.replica_table), 3) * 2
  end

  @doc """
  The leader will rotate based on the curr_view number.
  """
  @spec get_current_leader(%HotStuff{}) :: any()
  def get_current_leader(state) do
    leader_index = rem(state.curr_view, length(state.replica_table))
    Enum.at(state.replica_table, leader_index)
  end

  @doc """
  This function transitions a process so it is a primary.
  """
  @spec become_leader(%HotStuff{}) :: no_return()
  def become_leader(state) do
    Logger.info("Process #{inspect(whoami())} become leader in view #{inspect(state.curr_view)}")
    state = %{state | is_leader: true, current_leader: whoami()}
    leader(state, %{type: :new_view, collector: [state.prepared_qc]})
  end

  @doc """
  This function implements the state machine for a process
  that is currently a primary.
  """
  @spec leader(%HotStuff{is_leader: true}, any()) :: no_return()
  # Use the `extra_state` to track the phase leader is in
  # and the number of different type of qc it have received in given phase
  def leader(state, extra_state) do
    receive do
      {sender,
       %HotStuff.Msg{
         type: type,
         view_number: view_number,
         node: log_entry,
         justify: qc
       }} ->
        # Tracking :new_view message received from followers and put them into the collector
        if matching_msg(type, view_number, extra_state.type, state.curr_view - 1) do
          extra_state = %{extra_state | collector: qc ++ extra_state.collector}
          # Wait for (n-f-1) = 2f :new_view message from the followers
          if get_majority(state, extra_state) do
            high_qc =
              extra_state.collector
              |> Enum.max_by(fn x -> x.view_number end)

            # TODO: define node_to_propose here
            node_to_propose = HotStuff.LogEntry.empty()
            # Create the node to be proposed by extending from the high_qc node
            node_proposal = create_leaf(high_qc, node_to_propose)
            # create the prepare message and broadcast to all the follwers
            prepare_msg = generate_msg(state, :prepare, node_proposal, high_qc)
            broadcast_to_others(state, {:prepare, prepare_msg})
            # The leader enters the prepare phase after the broadcast
            extra_state = %{extra_state | type: :prepare, collector: []}
          end
        else
          Logger.info("leader #{inspect(whoami())} receive unexpected message")
        end

        leader(state, extra_state)

      {sender,
       %HotStuff.VoteMsg{
         message: message,
         partialSig: partial_sig
       }} ->
        # For each phase, collect the partial sig received from follower
        if matching_msg(message.type, message.view_number, extra_state.type, state.curr_view) do
          extra_state = %{extra_state | collector: partial_sig ++ extra_state.collector}
          # Wait for (n-f) votes
          if get_majority(state, extra_state) do
            # combine the partial signature through threshold signature
            qc = create_quorum_cert(message, extra_state.collector)

            case extra_state.type do
              :prepare ->
                state = %{state | prepared_qc: qc}
                extra_state = %{extra_state | type: :precommit}

              :precommit ->
                state = %{state | precommit_qc: qc}
                extra_state = %{extra_state | type: :commit}

              :commit ->
                state = %{state | commit_qc: qc}
                extra_state = %{extra_state | type: :decide}
            end

            msg = generate_msg(state, extra_state.type, nil, qc)
            broadcast_to_others(state, {extra_state.type, msg})

            # Leader go into next phase or become a follower once sending the decide message
            if extra_state.type == :decide do
              state = %{state | curr_view: state.curr_view + 1}
              become_replica(state)
            else
              extra_state = %{extra_state | collector: []}
            end
          end
        end

        leader(state, extra_state)

      # Message received from client
      {sender, :nop} ->
        Logger.info("Leader #{whoami} receive client nop request")
        state = %{state | node_to_propose: HotStuff.LogEntry.nop(state.curr_view, sender, nil)}
        leader(state, extra_state)

      {sender, {:enq, item}} ->
        Logger.info("Leader #{whoami} receive client enq request")

        state = %{
          state
          | node_to_propose: HotStuff.LogEntry.enqueue(state.curr_view, sender, item, nil)
        }

        leader(state, extra_state)

      {sender, :deq} ->
        Logger.info("Leader #{whoami} receive client deq request")

        state = %{
          state
          | node_to_propose: HotStuff.LogEntry.dequeue(state.curr_view, sender, nil)
        }

        leader(state, extra_state)
    end
  end

  @doc """
  This function makes a replica as backup
  """
  @spec become_replica(%HotStuff{is_leader: false}) :: no_return()
  def become_replica(state) do
    Logger.info(
      "Process #{inspect(whoami())} become follower in view #{inspect(state.curr_view)}"
    )

    state = %{state | is_leader: false, current_leader: get_current_leader(state)}
    replica(state, %{type: :prepare})
  end

  @doc """

  """
  @spec replica(%HotStuff{is_leader: false}, any()) :: no_return()
  def replica(state, extra_state) do
    receive do
      # Message received from leader
      {sender,
       {:prepare,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node_proposal,
          justify: high_qc
        }}} ->
        if sender == state.current_leader &&
             matching_msg(type, view_number, extra_state.type, state.curr_view) do
              if node_proposal.parent == :crypto.hash(:sha256, high_qc.node) &&
               safeNode(state, node_proposal, high_qc) do
            vote_msg = generate_votemsg(state, type, node_proposal, nil)
            send(state.current_leader, vote_msg)
          end
        end

        replica(state, %{extra_state | type: :precommit})

      {sender,
       {:precommit,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: prepared_qc
        }}} ->
        if sender == state.current_leader &&
             matching_qc(prepared_qc, extra_state.type, state.curr_view) do
          %{state | prepared_qc: prepared_qc}
          vote_msg = generate_votemsg(state, type, prepared_qc.node, nil)
          send(state.current_leader, vote_msg)
        end

        replica(state, %{extra_state | type: :commit})

      {sender,
       {:commit,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: precommit_qc
        }}} ->
        if sender == state.current_leader &&
             matching_qc(precommit_qc, extra_state.type, state.curr_view) do
          %{state | locked_qc: precommit_qc}
          vote_msg = generate_votemsg(state, type, precommit_qc.node, nil)
          send(state.current_leader, vote_msg)
        end

        replica(state, %{extra_state | type: :decide})

      {sender,
       {:decide,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: commit_qc
        }}} ->
        if sender == state.current_leader &&
             matching_qc(commit_qc, extra_state.type, state.curr_view) do
          # Execute the commited logEntry and response to the client
          entry = commit_qc.node
          {{requester, return_value}, new_state} = commit_log_entry(state, entry)
          send(requester, return_value)
        end
        #Increment the view number and check if it will turn into leader in the next view
        state = %{state | curr_view: state.curr_view + 1}
        if (get_current_leader(state) == whoami()) do
          become_leader(state)
        else
          replica(state, %{extra_state | type: :prepare})
        end

      # Messages from external clients. Redirect the client to leader of the view
      {sender, :nop} ->
        Logger.info("Follower #{whoami} receive client nop request")
        send(sender, {:redirect, state.current_leader})
        replica(state, extra_state)

      {sender, {:enq, item}} ->
        Logger.info("Follower #{whoami} receive client enq request")
        send(sender, {:redirect, state.current_leader})
        replica(state, extra_state)

      {sender, :deq} ->
        Logger.info("Follower #{whoami} receive client enq request")
        send(sender, {:redirect, state.current_leader})
        replica(state, extra_state)
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
