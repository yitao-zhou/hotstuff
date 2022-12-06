defmodule PBFT do
  @moduledoc """
  An implementation of the PBFT.
  """
  import Emulation, only: [send: 2, timer: 1, now: 0, whoami: 0]

  import Kernel,
    except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

  require Fuzzers

  require Logger

  # This structure contains all the process state
  # required by the PBFT protocol.
  defstruct(
    replicaTable: nil,
    viewID: nil,
    primaryID: nil,
    is_primary: nil,
    currentState: nil,
    prePrepareLog: nil,
    prepareLog: nil,
    lastReply: nil,
    sequenceNumber: nil,
    pub_keys: nil,
    priv_key: nil,
    low_watermark: nil,
    high_watermark: nil
  )

  @doc """
  Create state for an initial PBFT cluster. Each
  process should get an appropriately updated version
  of this state.
  """
  @spec new_configuration(
          [atom()],
          non_neg_integer(),
          non_neg_integer(),
          %{}
        ) :: %PBFT{}
  def new_configuration(
        replicatable,
        viewid,
        primaryid,
        pub_keys
      ) do
    %PBFT{
      replicaTable: replicatable,
      viewID: viewid,
      primaryID: primaryid,
      is_primary: false,
      currentState: nil,
      prePrepareLog: %{},
      prepareLog: %{},
      lastReply: %{},
      sequenceNumber: 0,
      pub_keys: pub_keys,
      priv_key: nil,
      low_watermark: 0,
      high_watermark: 1000
    }
  end

  # Utility function to send a message to all
  # processes other than the caller.
  @spec broadcast_to_others(%PBFT{}, any()) :: [boolean()]
  defp broadcast_to_others(state, message) do
    me = whoami()

    state.replicaTable
    |> Enum.filter(fn pid -> pid != me end)
    |> Enum.map(fn pid -> send(pid, message) end)
  end

  # Utility function to get the signature from string and private key
  @spec get_signature(string(), any()) :: any()
  def get_signature(message_string, priv_key) do
    {_, signature} = ExPublicKey.sign(message_string, priv_key)
    signature
  end

  # Utility function to get the verification from string, signature and pub key
  @spec get_verification(string(), any(), any()) :: any()
  def get_verification(message_string, signature, pub_key) do
    {_, verify_result} = ExPublicKey.verify(message_string, signature, pub_key)
    verify_result
  end

  # Utility function to get digest of message
  @spec get_digest(string()) :: any()
  def get_digest(operation_stringify) do
    Base.encode16(:crypto.hash(:sha256, operation_stringify))
  end

  # Utility function to stringify message of three inputs
  @spec stringify_message_three(any(), any(), any()) :: string()
  def stringify_message_three(a, b, c) do
    stringify = to_string(a)
                <> to_string(b)
                <> to_string(c)
    stringify
  end

  # Utility function to stringify message of four inputs
  @spec stringify_message_four(any(), any(), any(), any()) :: string()
  def stringify_message_four(a, b, c, d) do
    stringify = to_string(a)
                <> to_string(b)
                <> to_string(c)
                <> to_string(d)
    stringify
  end

  # Utility function to stringify message of five inputs
  @spec stringify_message_five(any(), any(), any(), any(), any()) :: string()
  def stringify_message_five(a, b, c, d, e) do
    stringify = to_string(a)
                <> to_string(b)
                <> to_string(c)
                <> to_string(d)
                <> to_string(e)
    stringify
  end

  @doc """
  This function transitions a process so it is
  a primary.
  """
  @spec become_primary(%PBFT{}, any()) :: no_return()
  def become_primary(state, priv_key) do
    state = %{state | is_primary: true, priv_key: priv_key}
    primary(state, %{}, %{})
  end

  @doc """
  This function implements the state machine for a process
  that is currently a primary.
  """
  @spec primary(%PBFT{is_primary: true}, any(), any()) :: no_return()
  def primary(state, prepared_count, committed_local_count) do
    receive do
      {sender, %PBFT.RequestMessage{
        operation: operation,
        timestamp: timestamp,
        client: client,
        signature: signature
      }} ->
        Logger.info("Primary #{whoami()} received request from client.")
        operation_stringify = stringify_message_three(operation, timestamp, client)
        
        verify_result = get_verification(operation_stringify, signature, Map.get(state.pub_keys, sender))
        
        if verify_result == true do
          v = state.viewID
          n = state.sequenceNumber
          state = %{state | sequenceNumber: state.sequenceNumber + 1}
          digest = get_digest(operation_stringify)
          preprepare_stringify = stringify_message_three(v, n, digest)
          signature_preprepare = get_signature(preprepare_stringify, state.priv_key)
          broadcast_to_others(state, PBFT.PrePrepareMessage.new(v, n, digest, signature_preprepare, PBFT.RequestMessage.new(operation, timestamp, client, signature)))
          state = %{state | prePrepareLog: Map.put(state.prePrepareLog, digest, PBFT.PrePrepareMessage.new(v, n, digest, signature_preprepare, PBFT.RequestMessage.new(operation, timestamp, client, signature)))}
          Logger.info("Primary #{whoami()} broadcasted a PrePrepare Message with digest #{digest}.")
          primary(state, prepared_count, committed_local_count)
        else 
          Logger.info("Primary #{whoami()} do not verify the signature of client #{sender}")
          primary(state, prepared_count, committed_local_count)
        end
        
      {sender, %PBFT.PrepareMessage{
          viewID: viewID,
          sequenceNumber: sequenceNumber,
          digest: digest,
          backupID: backupID,
          signature: signature,
        }} ->
          signature_matches = get_verification(stringify_message_four(viewID, sequenceNumber, digest, backupID), signature, Map.get(state.pub_keys, sender))
          view_matches = viewID == state.viewID
          sequenceNumber_in_range = 
            if sequenceNumber >= state.low_watermark and sequenceNumber <= state.high_watermark do
              true
            end
           
          if signature_matches == true and view_matches == true and sequenceNumber_in_range == true do
            prepared_count = 
              if Map.has_key?(prepared_count, digest) do
                if Enum.member?(prepared_count[digest][:replicas], sender) do
                  prepared_count
                else
                  get_and_update_in(prepared_count, [digest, :replicas], &{&1, &1 ++ [sender]}) |> elem(1)
                end
              else
                put_in(prepared_count, [digest], %{replicas: [sender], broadcasted: false})
              end

            # div((length(state.replicaTable)-1),3) * 2 is 2f
            if prepared_count[digest][:broadcasted] == false and length(prepared_count[digest][:replicas]) >= div((length(state.replicaTable)-1),3) * 2 and Map.has_key?(state.prePrepareLog, digest) and state.prePrepareLog[digest].viewID == viewID and state.prePrepareLog[digest].sequenceNumber == sequenceNumber  do
              # entering here means prepared(m, v, n, i) becomes true, and broadcasted is the same meaning as prepared
              prepared_count = get_and_update_in(prepared_count, [digest, :broadcasted], &{&1, true})|> elem(1)
              commit_signature = get_signature(stringify_message_four(viewID, sequenceNumber, digest, whoami()), state.priv_key)
              broadcast_to_others(state, PBFT.CommitMessage.new(viewID, sequenceNumber, digest, whoami(), commit_signature))
              primary(state, prepared_count, committed_local_count)
            end

            Logger.info("Primary #{whoami()} broadcasted a Commit Message with digest #{digest}.")
            primary(state, prepared_count, committed_local_count)
        else

            Logger.info("Primary #{whoami()} do not verify the Prepare Message from #{sender}")
            primary(state, prepared_count, committed_local_count)
        end

    {sender, %PBFT.CommitMessage{
      viewID: viewID,
      sequenceNumber: sequenceNumber,
      digest: digest,
      replicaID: replicaID,
      signature: signature
      }} ->
        signature_matches = get_verification(stringify_message_four(viewID, sequenceNumber, digest, replicaID), signature, Map.get(state.pub_keys, sender))
        view_matches = viewID == state.viewID
        sequenceNumber_in_range = 
          if sequenceNumber >= state.low_watermark and sequenceNumber <= state.high_watermark do
            true
          end

        Logger.info("#{whoami()} at commit stage 1 #{inspect(committed_local_count)}")

        if signature_matches == true and view_matches == true and sequenceNumber_in_range == true do
          committed_local_count = 
            if Map.has_key?(committed_local_count, digest) do
              if Enum.member?(committed_local_count[digest][:replicas], sender) do
                committed_local_count
              else
                get_and_update_in(committed_local_count, [digest, :replicas], &{&1, &1 ++ [sender]}) |> elem(1)
              end
            else
              put_in(committed_local_count, [digest], %{replicas: [sender], broadcasted: false})
            end

          Logger.info("#{whoami()} at commit stage 2 #{inspect(committed_local_count)}")

          # checking if prepared of this replica is true and this replica has not been added to committed local
          committed_local_count = 
            if not Enum.member?(committed_local_count[digest][:replicas], whoami()) and prepared_count[digest][:broadcasted] == true do
              get_and_update_in(committed_local_count, [digest, :replicas], &{&1, &1 ++ [whoami()]}) |> elem(1)
            else
              committed_local_count
            end

          Logger.info("#{whoami()} at commit stage 3 #{inspect(committed_local_count)}")
          
          # check if commited local has accepted 2f + 1 commits 
          if committed_local_count[digest][:broadcasted] == false and length(committed_local_count[digest][:replicas]) >= (div((length(state.replicaTable)-1),3) * 2 + 1) do
            committed_local_count = get_and_update_in(committed_local_count, [digest, :broadcasted], &{&1, true}) |> elem(1)
            # committed-local is true, execute the operations
            message_to_execute = state.prePrepareLog[digest].message
            # suppose the operation is simple, which is calculate the digest
            operation_digest = get_digest(message_to_execute.operation)

            # send reply back to client
            reply_signature = get_signature(stringify_message_five(viewID, message_to_execute.timestamp, message_to_execute.client, whoami(), operation_digest), state.priv_key)
            reply_message = PBFT.ReplyMessage.new(viewID, message_to_execute.timestamp, message_to_execute.client, whoami(), operation_digest, reply_signature)
            
            if state.lastReply == %{} do
              send(message_to_execute.client, reply_message)
              state = %{state | lastReply: reply_message}
              primary(state, prepared_count, committed_local_count)
            else
              if state.lastReply.timestamp > message_to_execute.timestamp do
                primary(state, prepared_count, committed_local_count)
              else
                send(message_to_execute.client, reply_message)
                state = %{state | lastReply: reply_message}
                primary(state, prepared_count, committed_local_count)
              end
            end
            primary(state, prepared_count, committed_local_count)
          end
          primary(state, prepared_count, committed_local_count)

        else 
          primary(state, prepared_count, committed_local_count)
        end

      {sender, :nop} ->
        send(sender, :ok)
    end
  end

  @doc """
  This function makes a replica as backup
  """
  @spec become_backup(%PBFT{is_primary: false}, any()) :: no_return()
  def become_backup(state, priv_key) do
    state = %{state | is_primary: false, priv_key: priv_key}
    backup(state, %{}, %{})
  end

  @doc """
  
  """
  @spec backup(%PBFT{is_primary: false}, any(), any()) :: no_return()
  def backup(state, prepared_count, committed_local_count) do
    receive do
      {sender, %PBFT.PrePrepareMessage{
        viewID: viewID,
        sequenceNumber: sequenceNumber,
        digest: digest,
        signature: signature,
        message: message
      }} ->
        preprepare_stringify = stringify_message_three(viewID, sequenceNumber, digest)
        verify_result = get_verification(preprepare_stringify, signature, Map.get(state.pub_keys, sender))
        
        operation_stringify = stringify_message_three(message.operation, message.timestamp, message.client)
        digest_same = get_digest(operation_stringify) == digest
        
        view_same = viewID == state.viewID

        # TODO: it has not accepted a pre-prepare message for view v and sequence number n containing a different digest

        sequenceNumber_in_range = 
          if sequenceNumber >= state.low_watermark and sequenceNumber <= state.high_watermark do
            true
          end
        
        if verify_result == true and digest_same == true and view_same == true and sequenceNumber_in_range == true do
          v = viewID
          n = sequenceNumber
          d = digest
          i = whoami()
          prepare_stringify = stringify_message_four(v, n, d, i)
          prepare_signature = get_signature(prepare_stringify, state.priv_key)
          broadcast_to_others(state, PBFT.PrepareMessage.new(v, n, d, i, prepare_signature))
          state = %{state | prepareLog: Map.put(state.prepareLog, d, PBFT.PrepareMessage.new(v, n, d, i, prepare_signature)), 
                            prePrepareLog: Map.put(state.prePrepareLog, d, %PBFT.PrePrepareMessage{viewID: viewID, sequenceNumber: sequenceNumber, digest: digest, signature: signature, message: message})
                          }
          Logger.info("Backup #{whoami()} verifies the PrePrepare Message of digest #{digest} from #{sender}, broadcast a Prepare Message")
          backup(state, prepared_count, committed_local_count)
        else
          Logger.info("Backup #{whoami()} do NOT verify the PrePrepare Message of digest #{digest} from #{sender}")
          backup(state, prepared_count, committed_local_count)
        end
        

      {sender, %PBFT.PrepareMessage{
        viewID: viewID,
        sequenceNumber: sequenceNumber,
        digest: digest,
        backupID: backupID,
        signature: signature,
        }} ->
          signature_matches = get_verification(stringify_message_four(viewID, sequenceNumber, digest, backupID), signature, Map.get(state.pub_keys, sender))
          view_matches = viewID == state.viewID
          sequenceNumber_in_range = 
            if sequenceNumber >= state.low_watermark and sequenceNumber <= state.high_watermark do
              true
            end
           
          if signature_matches == true and view_matches == true and sequenceNumber_in_range == true do
            prepared_count = 
              if Map.has_key?(prepared_count, digest) do
                if Enum.member?(prepared_count[digest][:replicas], sender) do
                  prepared_count
                else
                  get_and_update_in(prepared_count, [digest, :replicas], &{&1, &1 ++ [sender]}) |> elem(1)
                end
              else
                put_in(prepared_count, [digest], %{replicas: [sender], broadcasted: false})
              end

            # div((length(state.replicaTable)-1),3) * 2 is 2f
            if prepared_count[digest][:broadcasted] == false and length(prepared_count[digest][:replicas]) >= div((length(state.replicaTable)-1),3) * 2 and Map.has_key?(state.prePrepareLog, digest) and state.prePrepareLog[digest].viewID == viewID and state.prePrepareLog[digest].sequenceNumber == sequenceNumber  do
              # entering here means prepared(m, v, n, i) becomes true, and broadcasted is the same meaning as prepared
              prepared_count = get_and_update_in(prepared_count, [digest, :broadcasted], &{&1, true}) |> elem(1)
              commit_signature = get_signature(stringify_message_four(viewID, sequenceNumber, digest, whoami()), state.priv_key)
              broadcast_to_others(state, PBFT.CommitMessage.new(viewID, sequenceNumber, digest, whoami(), commit_signature))
              backup(state, prepared_count, committed_local_count)
            end

            Logger.info("Backup #{whoami()} broadcasted a Commit Message with digest #{digest}.")
            backup(state, prepared_count, committed_local_count)
        else

            Logger.info("Backup #{whoami()} do not verify the Prepare Message from #{sender}")
            backup(state, prepared_count, committed_local_count)
        end

      {sender, %PBFT.CommitMessage{
        viewID: viewID,
        sequenceNumber: sequenceNumber,
        digest: digest,
        replicaID: replicaID,
        signature: signature
      }} ->
        signature_matches = get_verification(stringify_message_four(viewID, sequenceNumber, digest, replicaID), signature, Map.get(state.pub_keys, sender))
        view_matches = viewID == state.viewID
        sequenceNumber_in_range = 
          if sequenceNumber >= state.low_watermark and sequenceNumber <= state.high_watermark do
            true
          end

        Logger.info("#{whoami()} at commit stage 1 #{inspect(committed_local_count)}")

        if signature_matches == true and view_matches == true and sequenceNumber_in_range == true do
          committed_local_count = 
            if Map.has_key?(committed_local_count, digest) do
              if Enum.member?(committed_local_count[digest][:replicas], sender) do
                committed_local_count
              else
                get_and_update_in(committed_local_count, [digest, :replicas], &{&1, &1 ++ [sender]}) |> elem(1)
              end
            else
              put_in(committed_local_count, [digest], %{replicas: [sender], broadcasted: false})
            end
            
          Logger.info("#{whoami()} at commit stage 2 #{inspect(committed_local_count)}")

          # checking if prepared of this replica is true and this replica has not been added to committed local
          committed_local_count = 
            if not Enum.member?(committed_local_count[digest][:replicas], whoami()) and prepared_count[digest][:broadcasted] == true do
              get_and_update_in(committed_local_count, [digest, :replicas], &{&1, &1 ++ [whoami()]}) |> elem(1)
            else
              committed_local_count
            end

          Logger.info("#{whoami()} at commit stage 3 #{inspect(committed_local_count)}")

          # check if commited local has accepted 2f + 1 commits 
          if committed_local_count[digest][:broadcasted] == false and length(committed_local_count[digest][:replicas]) >= (div((length(state.replicaTable)-1),3) * 2 + 1) do
            committed_local_count = get_and_update_in(committed_local_count, [digest, :broadcasted], &{&1, true}) |> elem(1)
            # committed-local is true, execute the operations
            message_to_execute = state.prePrepareLog[digest].message
            # suppose the operation is simple, which is calculate the digest
            operation_digest = get_digest(message_to_execute.operation)
            
            # send reply back to client
            reply_signature = get_signature(stringify_message_five(viewID, message_to_execute.timestamp, message_to_execute.client, whoami(), operation_digest), state.priv_key)
            reply_message = PBFT.ReplyMessage.new(viewID, message_to_execute.timestamp, message_to_execute.client, whoami(), operation_digest, reply_signature)
            
            if state.lastReply == %{} do
              send(message_to_execute.client, reply_message)
              state = %{state | lastReply: reply_message}
              backup(state, prepared_count, committed_local_count)
            else
              if state.lastReply.timestamp > message_to_execute.timestamp do
                backup(state, prepared_count, committed_local_count)
              else
                send(message_to_execute.client, reply_message)
                state = %{state | lastReply: reply_message}
                backup(state, prepared_count, committed_local_count)
              end
            end

            backup(state, prepared_count, committed_local_count)
          end
          backup(state, prepared_count, committed_local_count)

        else 
          backup(state, prepared_count, committed_local_count)
        end
        

      {sender, :nop} ->
        send(sender, :ok)
    end
  end
end

defmodule PBFT.Client do
  import Emulation, only: [send: 2, whoami: 0]

  import Kernel,
    except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

  require Logger

  @moduledoc """
  A client that can be used to connect and send
  requests to the RSM.
  """
  alias __MODULE__
  @enforce_keys [:replicas]
  defstruct(replicas: nil, view_number: nil, timestamp: nil, pub_keys: nil, priv_key: nil)

  # Utility function to get the signature from string and private key
  @spec get_signature(string(), any()) :: any()
  def get_signature(message_string, priv_key) do
    {_, signature} = ExPublicKey.sign(message_string, priv_key)
    signature
  end

  # Utility function to get the verification from string, signature and pub key
  @spec get_verification(string(), any(), any()) :: any()
  def get_verification(message_string, signature, pub_key) do
    {_, verify_result} = ExPublicKey.verify(message_string, signature, pub_key)
    verify_result
  end
  
  @doc """
  Construct a new PBFT Client. 
  """
  @spec new_client(atom(), %{}, any()) :: %Client{}
  def new_client(member, pub_keys, priv_key) do
    %Client{replicas: member, view_number: 0, timestamp: 0, pub_keys: pub_keys, priv_key: priv_key}
  end

  @doc """
  Send a nop request to the RSM.
  """
  @spec nop(%Client{}) :: {:ok, %Client{}}
  def nop(client) do
    me = whoami()
    Logger.info("Client #{me} sends a nop message to primary.")
    # find current primary by view number
    primary = Enum.at(client.replicas, rem(client.view_number, length(client.replicas)))
    send(primary, :nop)

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
  @spec send_message(%Client{}, any()) :: {:ok, %Client{}}
  def send_message(client, message) do
    me = whoami()
    
    Logger.info("Client #{me} sends a work message to primary.")
    # find current primary by view number
    primary = Enum.at(client.replicas, rem(client.view_number, length(client.replicas)))

    operation_stringify = to_string(message) <> to_string(client.timestamp) <> to_string(me)

    signature = get_signature(operation_stringify, client.priv_key)

    send(primary, PBFT.RequestMessage.new(message, client.timestamp, me, signature))
    
    client = %{client | timestamp: client.timestamp + 1}
    
    wait_reply(client, 0)
  end

  @doc """
  This is a paired function with send_message to wait for f + 1 replies from replicas
  """
  @spec wait_reply(%Client{}, non_neg_integer()) :: {:ok, %Client{}}
  def wait_reply(client, count) do
    me = whoami()
    
    Logger.info("Client #{me} waits for f + 1 replies")

    receive do
      {sender, %PBFT.ReplyMessage{
        viewID: viewID,
        timestamp: timestamp,
        client: received_client,
        replicaID: replicaID,
        result: result,
        signature: signature
      }} ->
        verification = get_verification(to_string(viewID) <> to_string(timestamp) <> to_string(received_client) <> to_string(replicaID) <> to_string(result), signature, Map.get(client.pub_keys, sender))
        
        count = 
          if verification == true do
            count + 1
          else
            count
          end
        
        if count >= (div((length(client.replicas)-1),3) + 1) do
          send(:ok, client)
        else
          wait_reply(client, count)
        end
    end
  end
end
