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
    log: nil,
    committedMsgs: nil
  )

  @doc """
  Create state for an initial PBFT cluster. Each
  process should get an appropriately updated version
  of this state.
  """
  @spec new_configuration(
          [atom()],
          non_neg_integer(),
          non_neg_integer()
        ) :: %PBFT{}
  def new_configuration(
        replicatable,
        viewid,
        primaryid
      ) do
    %PBFT{
      replicaTable: replicatable,
      viewID: viewid,
      primaryID: primaryid,
      is_primary: false,
      currentState: nil,
      log: %{},
      committedMsgs: %{},
    }
  end

  @doc """
  This function transitions a process so it is
  a primary.
  """
  @spec become_primary(%PBFT{}) :: no_return()
  def become_primary(state) do
    state = %{state | is_primary: true}
    primary(state, %{})
  end

  @doc """
  This function implements the state machine for a process
  that is currently a primary.
  """
  @spec primary(%PBFT{is_primary: true}, any()) :: no_return()
  def primary(state, extra_state) do
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

defmodule PBFT.Client do
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
