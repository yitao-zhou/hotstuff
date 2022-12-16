defmodule BasicTest do
    use ExUnit.Case
    doctest HotStuff
    import Emulation, only: [spawn: 2, send: 2]
  
    import Kernel,
      except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]
  
    test "Nothing crashes during startup" do
      Emulation.init()
      Emulation.append_fuzzers([Fuzzers.delay(2)])


      base_config =
      HotStuff.new_configuration([:a, :b, :c, :d], :a)
  
      spawn(:a, fn -> HotStuff.become_leader(base_config) end)
    #   spawn(:b, fn -> PBFT.become_backup(base_config) end)
    #   spawn(:c, fn -> PBFT.become_backup(base_config) end)
    #   spawn(:d, fn -> PBFT.become_backup(base_config) end)
  
      client =
        spawn(:client, fn ->
          client = HotStuff.Client.new_client(:a)
          HotStuff.Client.nop(client)
  
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
end