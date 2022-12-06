defmodule BasicTest do
    use ExUnit.Case
    doctest PBFT
    import Emulation, only: [spawn: 2, send: 2]
  
    import Kernel,
      except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]
  
    test "Nothing crashes during startup" do
      Emulation.init()
      Emulation.append_fuzzers([Fuzzers.delay(2)])


      base_config =
        PBFT.new_configuration([:a, :b, :c, :d], 0, :a)
  
      spawn(:a, fn -> PBFT.become_primary(base_config) end)
    #   spawn(:b, fn -> PBFT.become_backup(base_config) end)
    #   spawn(:c, fn -> PBFT.become_backup(base_config) end)
    #   spawn(:d, fn -> PBFT.become_backup(base_config) end)
  
      client =
        spawn(:client, fn ->
          client = PBFT.Client.new_client(:a)
          PBFT.Client.nop(client)
  
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