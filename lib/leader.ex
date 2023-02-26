defmodule Leader do

#Setters
defp proposals(self, v) do Map.put(self, :proposals, v) end
defp active(self, v) do Map.put(self, :active, v) end
defp ballot_num(self, v) do Map.put(self, :ballot_num, v) end
defp acceptors(self, v) do Map.put(self, :acceptors, v) end
defp replicas(self, v) do Map.put(self, :replicas, v) end
defp active_commanders(self, v) do Map.put(self, :active_commanders, v) end

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
    proposals:  [],
    active_commanders: []
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
      if ballot_num == self.ballot_num do
        self = self |> proposals(update(self.proposals, pmax(pvals)))
        new_commanders = for {s, c} <- self.proposals, into: [], do: (
          spawn(Commander, :start, [self.config, self(), self.acceptors, self.replicas, {self.ballot_num, s, c}])
          send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})
          {self.ballot_num, s, c})
        self = self |> active_commanders(new_commanders ++ self.active_commanders)
        self |> active(true)
      else
        self
      end
    {:preempted, {r, leader}} ->
      {self_r, self_leader} = self.ballot_num
      if r > self_r or (r == self_r and leader > self_leader) do
        send leader, {:ping, self()}
        wait_on_leader(leader, self())
        self = self |> active(false)
        self = self |> ballot_num({r + 1, self()})
        spawn(Scout, :start, [self.config, self(), self.acceptors, self.ballot_num])
        send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})
        self
      else
        self
      end
    {:commander_finished, ballot_num, s, c} ->
      self |> active_commanders(self.active_commanders -- [{ballot_num, s, c}])
    {:ping, waiting_leader} ->
      if length(self.active_commanders) > 0 do
        send waiting_leader, {:ping_back}
      end
      self
  end

  self |> next()
end

defp wait_on_leader(leader, self) do
  receive do
    {:ping_back} ->
      Process.sleep(1)
      send leader, {:ping, self}
      wait_on_leader(leader, self)
  after
    100 -> nil
  end
end

end
