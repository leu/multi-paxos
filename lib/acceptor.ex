defmodule Acceptor do

#Setters
defp ballot_num(self, v) do Map.put(self, :ballot_num, v) end
defp accepted(self, v) do Map.put(self, :accepted, v) end

def start(config) do
  config = Configuration.node_info(config, "Acceptor")
  Debug.starting(config)

  self = %{
    config:     config,
    ballot_num: {-1, 0}, #we treat -1 as false
    accepted:   []
  }

  self |> next()
end

defp next(self) do
  self = receive do
    {:p1a, λ, b} ->
      self = if b > self.ballot_num do
        self |> ballot_num(b)
      else
        self
      end
      send λ, {:p1b, self(), self.ballot_num, self.accepted}
      self
    {:p2a, λ, {b, s, c}} ->
      self = if b == self.ballot_num do
        self |> accepted(self.accepted ++ [{b, s, c}])
      else
        self
      end
      send λ, {:p2b, self(), self.ballot_num}
      self
  end

  self |> next()
end

end
