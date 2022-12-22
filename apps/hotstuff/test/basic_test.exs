defmodule BasicTest do
  use ExUnit.Case
  doctest HotStuff
  import Emulation, only: [spawn: 2, send: 2]

  import Kernel,
    except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

  test "Nothing crashes during startup" do
    Emulation.init()
    Emulation.append_fuzzers([Fuzzers.delay(2)])

    base_config = HotStuff.new_configuration([:a, :b, :c, :d], :a, 20_000)

    spawn(:a, fn -> HotStuff.become_leader(base_config) end)
    spawn(:b, fn -> HotStuff.become_replica(base_config) end)
    spawn(:c, fn -> HotStuff.become_replica(base_config) end)
    spawn(:d, fn -> HotStuff.become_replica(base_config) end)

    client =
      spawn(:client, fn ->
        client = HotStuff.Client.new_client([:a, :b, :c, :d])
        # I should enqueue some random tasks
        HotStuff.Client.enq(client, 5)
        :timer.sleep(500)

        receive do
        after
          5_000 -> true
        end
      end)

    handle = Process.monitor(client)
    # Timeout.
    receive do
      {:DOWN, ^handle, _, _, _} -> true
    after
      30_000 -> assert false
    end
  after
    Emulation.terminate()
  end

  test "Operation works on RSM" do
    Emulation.init()
    Emulation.append_fuzzers([Fuzzers.delay(2)])

    base_config = HotStuff.new_configuration([:a, :b, :c, :d], :a, 20_000)

    spawn(:a, fn -> HotStuff.become_leader(base_config) end)
    spawn(:b, fn -> HotStuff.become_replica(base_config) end)
    spawn(:c, fn -> HotStuff.become_replica(base_config) end)
    spawn(:d, fn -> HotStuff.become_replica(base_config) end)

    client =
      spawn(:client, fn ->
        client = HotStuff.Client.new_client([:a, :b, :c, :d])
        {:ok, client} = HotStuff.Client.enq(client, 5)
        {{:value, v}, client} = HotStuff.Client.deq(client)
        assert v == 5
      end)

    handle = Process.monitor(client)

    receive do
      {:DOWN, ^handle, _, _, _} -> true
    after
      1000_000 -> assert false
    end
  after
    Emulation.terminate()
  end
end
