
# distributed algorithms, n.dulay 31 jan 2023
# coursework, paxos made moderately complex

defmodule Client do

# _________________________________________________________ Setter
def seqnum(self, v) do Map.put(self, :seqnum, v) end

def start(config, client_num, replicas) do
  config = Configuration.node_info(config, "Client", client_num)
  Debug.starting(config)

  quorum = case config.send_policy do
    :round_robin -> 1
    :broadcast   -> config.n_servers
    :quorum      -> div(config.n_servers + 1, 2)
  end # case

  self = %{
    config:     config,
    client_num: client_num,
    replicas:   Helper.list_to_map(replicas),
    quorum:     quorum,
    seqnum:     0,
  }

  Process.send_after(self(), :CLIENT_STOP, self.config.client_stop)
  self |> next()
end # start

defp next(self) do
  # Warning. Setting client_sleep to 0 may overload the system
  # with lots of requests and lots of spawned processes.

  receive do
  :CLIENT_STOP ->
    IO.puts "  Client #{self.client_num} going to sleep, sent = #{self.seqnum}"
    Process.sleep(:infinity)

  after self.config.client_sleep ->
    account1    = Enum.random 1..self.config.n_accounts
    account2    = Enum.random 1..self.config.n_accounts
    amount      = Enum.random 1..self.config.max_amount
    transaction = { :MOVE, amount, account1, account2 }

    self = self |> seqnum(self.seqnum + 1)
    cmd = { self(), self.seqnum, transaction }
    for r <- 1..self.quorum do
      replica = self.replicas[rem(self.seqnum+r, self.config.n_servers)]
      send replica, { :CLIENT_REQUEST, cmd }
    end # for

    if self.seqnum == self.config.max_requests do send self(), :CLIENT_STOP end

    self |> receive_replies()
         |> next()
  end
end # next

defp receive_replies(self) do
  receive do
    { :CLIENT_REPLY, _cid, _result } ->   # discard reply
      self |> receive_replies()
    after 0 ->
      self
  end # receive
end # receive_replies

end # Client
