# Daniel Simols (ds1920) and Benson Zhou (bz620)

defmodule Replica do
  # Setters
  defp leaders(self, v) do
    Map.put(self, :leaders, v)
  end

  defp requests(self, v) do
    Map.put(self, :requests, v)
  end

  defp decisions(self, v) do
    Map.put(self, :decisions, v)
  end

  defp proposals(self, v) do
    Map.put(self, :proposals, v)
  end

  defp slot_out(self, v) do
    Map.put(self, :slot_out, v)
  end

  defp slot_in(self, v) do
    Map.put(self, :slot_in, v)
  end

  def start(config, database) do
    config = Configuration.node_info(config, "Replica")
    Debug.starting(config)

    self = %{
      config: config,
      database: database,
      leaders: [],
      slot_in: 1,
      slot_out: 1,
      requests: [],
      proposals: MapSet.new(),
      decisions: MapSet.new()
    }

    self =
      receive do
        {:BIND, leaders} ->
          self |> leaders(leaders)
      end

    self |> next()
  end

  defp next(self) do
    self =
      receive do
        {:CLIENT_REQUEST, c} ->
          send(self.config.monitor, {:CLIENT_REQUEST, c})
          self |> requests([c] ++ self.requests)

        {:decision, s, c} ->
          self = self |> decisions(MapSet.put(self.decisions, {s, c}))
          perform_all(self)
      end

    self = propose(self)
    next(self)
  end

  defp perform_all(self) do
    ready_slot = get_slot(self.slot_out, self.decisions)

    if tuple_size(ready_slot) == 2 do
      ready_c = elem(ready_slot, 1)
      proposal = get_slot(self.slot_out, self.proposals)

      self =
        if tuple_size(proposal) == 2 do
          self = self |> proposals(MapSet.delete(self.proposals, proposal))
          proposal_c = elem(proposal, 1)

          if proposal_c != ready_c do
            self |> requests([proposal_c] ++ self.requests)
          else
            self
          end
        else
          self
        end

      self = perform(self, ready_c)
      perform_all(self)
    else
      self
    end
  end

  defp get_slot(s, list) do
    Enum.reduce(list, {}, fn {s_h, c_h}, exists ->
      if s_h == s do
        {s_h, c_h}
      else
        exists
      end
    end)
  end

  defp propose(self) do
    if self.slot_in < self.slot_out + self.config.window_size and
         length(self.requests) > 0 do
      [c | requests_tail] = self.requests

      self =
        if !slot_exists?(self.slot_in, self.decisions) do
          self = self |> requests(requests_tail)
          self = self |> proposals(MapSet.put(self.proposals, {self.slot_in, c}))

          for leader <- self.leaders do
            send(leader, {:propose, self.slot_in, c})
          end

          self
        else
          self
        end

      self = self |> slot_in(self.slot_in + 1)
      propose(self)
    else
      self
    end
  end

  defp slot_exists?(slot_in, decisions) do
    Enum.reduce(decisions, false, fn {s, _}, exists ->
      if s == slot_in do
        true
      else
        exists
      end
    end)
  end

  defp perform(self, {k, cid, op}) do
    if c_is_previous(self.slot_out, {k, cid, op}, self.decisions) do
      self |> slot_out(self.slot_out + 1)
    else
      send(self.database, {:EXECUTE, op})
      send(k, {:CLIENT_REPLY, cid, "request executed!"})
      self |> slot_out(self.slot_out + 1)
    end
  end

  defp c_is_previous(slot_out, cmd, decisions) do
    Enum.reduce(decisions, false, fn {s_h, cmd_h}, exists ->
      if cmd_h == cmd and s_h < slot_out do
        true
      else
        exists
      end
    end)
  end
end
