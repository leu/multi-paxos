
# written by Daniel Simols (ds1920) and Benson Zhou (bz620)

defmodule Acceptor do
  # Setters
  defp ballot_num(self, v) do
    Map.put(self, :ballot_num, v)
  end

  defp accepted(self, v) do
    Map.put(self, :accepted, v)
  end

  def start(config) do
    config = Configuration.node_info(config, "Acceptor")

    self = %{
      # we treat -1 as false
      ballot_num: {-1, 0},
      accepted: MapSet.new()
    }

    self |> next()
  end

  defp next(self) do
    self =
      receive do
        {:p1a, λ, b} ->
          self =
            # adopts the higher ballot number
            if b > self.ballot_num do
              self |> ballot_num(b)
            else
              self
            end
          # sends current ballot number and all pvalues accepted thus far by the acceptor
          send(λ, {:p1b, self(), self.ballot_num, self.accepted})
          self

        {:p2a, λ, {b, s, c}} ->
          self =
            # accepts the pvalue only if ballot number matches
            if b == self.ballot_num do
              self |> accepted(MapSet.put(self.accepted, {b, s, c}))
            else
              self
            end
          # sends current ballot number
          send(λ, {:p2b, self(), self.ballot_num})
          self
      end

    self |> next()
  end
end
