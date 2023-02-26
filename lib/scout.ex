# Daniel Simols (ds1920) and Benson Zhou (bz620)

defmodule Scout do
  # Setters
  defp pvalues(self, v) do
    Map.put(self, :pvalues, v)
  end

  defp waitfor(self, v) do
    Map.put(self, :waitfor, v)
  end

  def start(config, λ, acceptors, new_b) do
    config = Configuration.node_info(config, "Scout")
    # Debug.starting(config)

    self = %{
      config: config,
      leader: λ,
      acceptors: acceptors,
      new_b: new_b,
      waitfor: acceptors,
      pvalues: MapSet.new()
    }

    for acceptor <- acceptors do
      send(acceptor, {:p1a, self(), new_b})
    end

    # for

    self |> next()
  end

  def next(self) do
    self =
      receive do
        {:p1b, a, b, r} ->
          if b == self.new_b do
            self = self |> pvalues(MapSet.union(self.pvalues, r))
            self = self |> waitfor(self.waitfor -- [a])

            if length(self.waitfor) < length(self.acceptors) / 2 do
              # returns a set of adopted messages to leader
              send(self.leader, {:adopted, self.new_b, self.pvalues})
              send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
              exit(:normal)
            end

            self
          else
            send(self.leader, {:preempted, b})
            send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
            exit(:normal)
          end
      end

    self |> next()
  end
end
