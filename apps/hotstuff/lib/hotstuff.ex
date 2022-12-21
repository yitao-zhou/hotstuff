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

    # highest qc which a replica voted pre-commit
    prepared_qc: nil,
    precommit_qc: nil,
    commit_qc: nil,
    # The highest qc (index the replica voted commit)
    locked_qc: nil,

    # In this simulation we assume leader will only propose one command at a time
    node_to_propose: nil,
    # In this simulation the RSM we are building is a queue
    queue: nil,

    # timer will be trigger if leader did not receive enough message from followers
    # Or follower hasn't heard from leader
    view_change_timeout: nil,
    view_change_timer: nil
  )

  @doc """
  Create state for an initial HotStuff cluster.
  Each process should get an appropriately updated version
  of this state.
  """
  @spec new_configuration(
          [atom()],
          atom(),
          non_neg_integer()
        ) :: %HotStuff{}
  def new_configuration(
        replica_table,
        leader,
        view_change_timeout
      ) do
    %HotStuff{
      replica_table: replica_table,
      curr_view: 0,
      current_leader: leader,
      is_leader: false,
      prepared_qc: nil,
      precommit_qc: nil,
      commit_qc: nil,
      locked_qc: nil,
      node_to_propose: nil,
      queue: :queue.new(),
      view_change_timeout: view_change_timeout
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

    if high_qc.node == nil do
      # TODO: I suppose this should be for the initial situation, I don't know if we need to change this
      %{proposal_node | parent: :crypto.hash(:sha256, to_string(high_qc.node))}
    else
      %{proposal_node | parent: :crypto.hash(:sha256, to_string(high_qc.node))}
    end
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
    # TODO: consider how to implement the safe node here
    true
  end

  @spec get_majority(%HotStuff{}, any()) :: boolean()
  def get_majority(state, extra_state) do
    IO.puts("#{length(extra_state.collector)}, #{Integer.floor_div(length(state.replica_table), 3) * 2}")
    
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
  Reset the view_change_timer on the process
  """
  @spec reset_view_change_timer(%HotStuff{}) :: %HotStuff{}
  defp reset_view_change_timer(state) do
    if state.view_change_timer != nil do
      Emulation.cancel_timer(state.view_change_timer)
    end

    %{state | view_change_timer: Emulation.timer(state.view_change_timeout, :view_change)}
  end

  @doc """
  This function transitions a process so it is a primary.
  """
  @spec become_leader(%HotStuff{}) :: no_return()
  def become_leader(state) do
    Logger.info("Process #{inspect(whoami())} become leader in view #{inspect(state.curr_view)}")

    state =
      state
      |> reset_view_change_timer()
      |> Map.put(:is_leader, true)
      |> Map.put(:current_leader, whoami())

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
      :view_change ->
        become_replica(%{state | curr_view: state.curr_view + 1})

      {sender,
       %HotStuff.Msg{
         type: type,
         view_number: view_number,
         node: log_entry,
         justify: qc
       }} ->
        # Tracking :new_view message received from followers and put them into the collector
        Logger.info("#{type}, #{view_number}, #{extra_state.type}, #{state.curr_view - 1}")

        if matching_msg(type, view_number, extra_state.type, state.curr_view - 1) or state.curr_view == 0 do
          extra_state = %{extra_state | collector: [qc] ++ extra_state.collector}
          IO.inspect(extra_state)
          # Wait for (n-f-1) = 2f :new_view message from the followers
          if get_majority(state, extra_state) do
            high_qc =
              if Enum.member?(extra_state.collector, nil) do
                # TODO: what to define when any of the collector info is nil?
                HotStuff.QC.new(type, view_number, log_entry, 1) # use 1 to temperarily represent sig
              else
                extra_state.collector
                  |> Enum.max_by(fn x -> x.view_number end)
              end

            # Create the node to be proposed by extending from the high_qc node
            IO.puts("high_qc is #{inspect(high_qc)}, node to propose is #{inspect(state.node_to_propose)}")
            node_proposal = create_leaf(high_qc, state.node_to_propose)
            # create the prepare message and broadcast to all the follwers
            prepare_msg = generate_msg(state, :prepare, node_proposal, high_qc)
            Logger.info("In view #{state.curr_view}, the client has broadcasted prepare msg to replicas")
            broadcast_to_others(state, {:prepare, prepare_msg})
            # The leader enters the prepare phase after the broadcast
            extra_state = %{extra_state | type: :prepare, collector: []}
            state = reset_view_change_timer(state)
            leader(state, extra_state)
          else
            Logger.info("Leader #{whoami()} don't get majority vote for #{type}")
            leader(state, extra_state)
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
          extra_state = %{extra_state | collector: [partial_sig] ++ extra_state.collector}
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
              state = reset_view_change_timer(state)
              leader(state, extra_state)
            end
          else
            leader(state, extra_state)
          end
        end

        leader(state, extra_state)

      # Message received from client
      {sender, :nop} ->
        Logger.info("Leader #{whoami} receive client nop request")
        state = %{state | node_to_propose: HotStuff.LogEntry.nop(state.curr_view, sender, nil)}
        reset_view_change_timer(state)
        leader(state, extra_state)

      {sender, {:enq, item}} ->
        Logger.info("Leader #{whoami} receive client enq request")

        state = %{
          state
          | node_to_propose: HotStuff.LogEntry.enqueue(state.curr_view, sender, item, nil)
        }

        reset_view_change_timer(state)
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

    state =
      state
      |> reset_view_change_timer()
      |> Map.put(:is_leader, false)
      |> Map.put(:current_leader, get_current_leader(state))

    newview_msg = generate_msg(state, :new_view, nil, state.prepared_qc)
    send(get_current_leader(state), newview_msg)
    replica(state, %{type: :prepare})
  end

  @doc """

  """
  @spec replica(%HotStuff{is_leader: false}, any()) :: no_return()
  def replica(state, extra_state) do
    receive do
      :view_change ->
        newview_msg = generate_msg(state, :new_view, nil, state.prepared_qc)
        send(get_current_leader(state), newview_msg)
        replica(state, %{extra_state | type: :prepare})

      # Message received from leader
      {sender,
       {:prepare,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node_proposal,
          justify: high_qc
        }}} ->
        Logger.info("#{whoami()} get to the prepare phase in view #{state.curr_view}")
        if sender == state.current_leader &&
             matching_msg(type, view_number, extra_state.type, state.curr_view) do
          if node_proposal.parent == :crypto.hash(:sha256, to_string(high_qc.node)) &&
               safeNode(state, node_proposal, high_qc) do
            vote_msg = generate_votemsg(state, type, node_proposal, nil)
            send(state.current_leader, vote_msg)
            state = reset_view_change_timer(state)
            replica(state, %{extra_state | type: :precommit})
          end
        end

        replica(state, extra_state)

      {sender,
       {:precommit,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: prepared_qc
        }}} ->
        Logger.info("#{whoami()} get to the precommit phase in view #{state.curr_view}")
        if sender == state.current_leader &&
             matching_qc(prepared_qc, extra_state.type, state.curr_view) do
          %{state | prepared_qc: prepared_qc}
          vote_msg = generate_votemsg(state, type, prepared_qc.node, nil)
          send(state.current_leader, vote_msg)
          state = reset_view_change_timer(state)
          replica(state, %{extra_state | type: :commit})
        end

        replica(state, extra_state)

      {sender,
       {:commit,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: precommit_qc
        }}} ->
        Logger.info("#{whoami()} get to the commit phase in view #{state.curr_view}")
        if sender == state.current_leader &&
             matching_qc(precommit_qc, extra_state.type, state.curr_view) do
          %{state | locked_qc: precommit_qc}
          vote_msg = generate_votemsg(state, type, precommit_qc.node, nil)
          send(state.current_leader, vote_msg)
          state = reset_view_change_timer(state)
          replica(state, %{extra_state | type: :decide})
        end

        replica(state, extra_state)

      {sender,
       {:decide,
        %HotStuff.Msg{
          type: type,
          view_number: view_number,
          node: node,
          justify: commit_qc
        }}} ->
        Logger.info("#{whoami()} get to the decide phase in view #{state.curr_view}")
        if sender == state.current_leader &&
             matching_qc(commit_qc, extra_state.type, state.curr_view) do
          # Execute the commited logEntry and response to the client
          entry = commit_qc.node
          {{requester, return_value}, new_state} = commit_log_entry(state, entry)
          Logger.info("Send the return value #{return_value} to requester #{requester}")
          send(requester, return_value)
        end

        # Increment the view number and check if it will turn into leader in the next view
        state = %{state | curr_view: state.curr_view + 1}

        if get_current_leader(state) == whoami() do

          Logger.info("#{whoami()} become leader in view #{state.curr_view}")
          become_leader(state)
        else
          replica(state, extra_state)
        end


      {sender, :nextViewInterrupt} ->
        # send a new view message to new leader
        newview_msg = generate_msg(state, :new_view, nil, state.prepared_qc)
        send(get_current_leader(state), newview_msg)
        replica(state, %{extra_state | type: :prepare})

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
  @enforce_keys [:replica_table, :current_leader]
  defstruct(replica_table: nil, current_leader: nil)

  @doc """
  Construct a new Hotstuff Client.
  """
  @spec new_client([], atom()) :: %Client{replica_table: [], current_leader: atom()}
  def new_client(replicas, member) do
    %Client{replica_table: replicas, current_leader: member}
  end

  @doc """
  Send a nop request to the RSM.
  """
  @spec client_request(%Client{}) :: {:ok, %Client{}}
  def client_request(client) do
    for replica <- client.replica_table, do: send(replica, :nextViewInterrupt)

    receive do
      # {_, {:redirect, new_leader}} ->
      #   nop(%{client | leader: new_leader})

      {_, :ok} ->
        {:ok, client}
    end
  end

  @doc """
  Send a nop request to the RSM.
  """
  @spec nop(%Client{}) :: {:ok, %Client{}}
  def nop(client) do
    leader = client.current_leader
    send(leader, :nop)

    receive do
      # {_, {:redirect, new_leader}} ->
      #   nop(%{client | leader: new_leader})

      {_, :ok} ->
        {:ok, client}
    end
  end

  @doc """
  Send an enqueue request to the RSM.
  """
  @spec enq(%Client{}, any()) :: {:ok, %Client{}}
  def enq(client, item) do
    leader = client.current_leader
    send(leader, {:enq, item})

    receive do
      {_, :ok} ->
        {:ok, client}

      {_, {:redirect, new_leader}} ->
        enq(%{client | leader: new_leader}, item)
    end
  end
end
