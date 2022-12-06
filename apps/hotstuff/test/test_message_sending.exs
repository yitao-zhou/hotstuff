defmodule TestMessageSending do
    use ExUnit.Case
    doctest PBFT
    import Emulation, only: [spawn: 2, send: 2]
  
    import Kernel,
      except: [spawn: 3, spawn: 1, spawn_link: 1, spawn_link: 3, send: 2]

    use ExPublicKey

    require Logger

    test "Sending message works" do
      Emulation.init()
      Emulation.append_fuzzers([Fuzzers.delay(2)])

      replicas = [:a, :b, :c, :d]
      client = [:client]

      pub_keys = %{}
      priv_keys = %{}
      
      priv_keys = 
      Enum.reduce(replicas ++ client, %{}, fn(x), priv_keys -> 
        {:ok, rsa_priv_key} = ExPublicKey.generate_key()
        Map.put(priv_keys, x, rsa_priv_key)
      end)

      pub_keys = 
      Enum.reduce(replicas ++ client, %{}, fn(x), pub_keys -> 
        {:ok, rsa_pub_key} = ExPublicKey.public_key_from_private_key(Map.get(priv_keys, x))
        Map.put(pub_keys, x, rsa_pub_key)
      end)

      base_config =
        PBFT.new_configuration(replicas, 0, :a, pub_keys)
  
      spawn(:a, fn -> PBFT.become_primary(base_config, Map.get(priv_keys, :a)) end)
      spawn(:b, fn -> PBFT.become_backup(base_config, Map.get(priv_keys, :b)) end)
      spawn(:c, fn -> PBFT.become_backup(base_config, Map.get(priv_keys, :c)) end)
      spawn(:d, fn -> PBFT.become_backup(base_config, Map.get(priv_keys, :d)) end)
  
      client =
        spawn(:client, fn ->
          client = PBFT.Client.new_client(replicas, pub_keys, Map.get(priv_keys, :client))
          Logger.info(client)
          PBFT.Client.send_message(client, "1+1")
  
          receive do
          after
            3_000 -> true
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