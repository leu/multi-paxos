defmodule MultipaxosTest do
  use ExUnit.Case
  doctest Multipaxos

  test "greets the world" do
    assert Multipaxos.hello() == :world
  end
end
