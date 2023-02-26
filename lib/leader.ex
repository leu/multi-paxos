defmodule Leader do

#Setters
defp proposals(self, v) do Map.put(self, :proposals, v) end
defp active(self, v) do Map.put(self, :active, v) end
defp ballot_num(self, v) do Map.put(self, :ballot_num, v) end
defp acceptors(self, v) do Map.put(self, :acceptors, v) end
defp replicas(self, v) do Map.put(self, :replicas, v) end

defp pmax(pvals) do
  map = Enum.reduce(pvals, %{},
    fn {b, s, c}, map ->
      if !Map.has_key?(map, s) or ({b_i, _} = map[s]; b_i < b) do
        Map.put(map, s, {b, c})
      else
        map
      end
    end)
  for {s, {_, c}} <- map, into: [], do: {s, c}
end

defp update(x, y) do
  result = Enum.into(y, %{})
  result = Enum.reduce(x, result,
    fn {s, c}, map ->
      if !Map.has_key?(map, s) do
        Map.put(map, s, c)
      else
        map
      end
    end
  )
  for e <- result, into: [], do: e
end

def start(config) do
  config = Configuration.node_info(config, "Leader")
  Debug.starting(config)

  self = %{
    config:     config,
    acceptors:  [],
    replicas:   [],
    ballot_num: {0, self()},
    active:     false,
    proposals:  []
  }

  self = receive do
    {:BIND, acceptors, replicas} ->
      self = self |> acceptors(acceptors)
      self |> replicas(replicas)
  end

  spawn(Scout, :start, [config, self(), self.acceptors, self.ballot_num])
  send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})

  self |> next()
end

defp next(self) do
  ballot_num = self.ballot_num
  self = receive do
    {:propose, s, c} ->
      proposal_exists = Enum.reduce(self.proposals, false,
        fn {s_p, _}, exists -> if s_p == s do true else exists end end)
      if !proposal_exists do
        self = self |> proposals([{s, c}] ++ self.proposals)
        if self.active do
          spawn(Commander, :start, [self.config, self(), self.acceptors, self.replicas, {self.ballot_num, s, c}])
          send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})

        end
        self
      else
        self
      end
    {:adopted, ballot_num, pvals} ->
      self = self |> proposals(update(self.proposals, pmax(pvals)))
      for {s, c} <- self.proposals do
        spawn(Commander, :start, [self.config, self(), self.acceptors, self.replicas, {self.ballot_num, s, c}])
        send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})

      end
      self |> active(true)
    {:preempted, {r, leader}} ->
      if {r, leader} > self.ballot_num do
        self = self |> active(false)
        self = self |> ballot_num({r + 1, self()})
        spawn(Scout, :start, [self.config, self(), self.acceptors, self.ballot_num])
        send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})

        self
      else
        self
      end
  end

  self |> next()
end

end
