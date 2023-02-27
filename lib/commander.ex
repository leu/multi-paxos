
# written by Daniel Simols (ds1920) and Benson Zhou (bz620)

defmodule Commander do
  # Setters
  defp waitfor(self, v) do
    Map.put(self, :waitfor, v)
  end

  def start(config, λ, acceptors, replicas, {at_b, s, c}) do
    config = Configuration.node_info(config, "Commander")

    self = %{
      config: config,
      leader: λ,
      acceptors: acceptors,
      replicas: replicas,
      at_b: at_b,
      s: s,
      c: c,
      waitfor: acceptors
    }

    for acceptor <- acceptors do
      send(acceptor, {:p2a, self(), {at_b, s, c}})
    end

    self |> next()
  end

  def next(self) do
    self =
      receive do
        {:p2b, a, b} ->
          if b == self.at_b do
            self = self |> waitfor(self.waitfor -- [a])

            # checks if the message is from majority of acceptors
            if length(self.waitfor) < length(self.acceptors) / 2 do
              # notifies replica of chose command in slot
              for replica <- self.replicas do
                send(replica, {:decision, self.s, self.c})
              end

              send(self.leader, {:COMMANDER_FINISHED, self()})
              send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
              exit(:normal)
            end

            self
          else
            # notifies leader of ballot with higher number
            send(self.leader, {:preempted, b})
            send(self.leader, {:COMMANDER_FINISHED, self()})
            send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
            exit(:normal)
          end
      end

    self |> next()
  end
end
