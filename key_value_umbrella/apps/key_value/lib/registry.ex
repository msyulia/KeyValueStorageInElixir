defmodule KeyValue.Registry do
  use GenServer

  ## Client API

  @doc """
  Starts the registry.

  `:name` is always required.
  """
  def start_link(opts) do
    server = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, server, opts)
  end

  @doc """
  Looks up the bucket pid for `bucket_name` stored in `server`.

  Returns `{:ok, pid}` if the bucket exists, `:error` otherwise.
  """
  def lookup(server, bucket_name) do
    case :ets.lookup(server, bucket_name) do
      [{^bucket_name, pid}] -> {:ok, pid}
      [] -> :error
    end
  end

  @doc """
  Ensures there is a bucket associated with the given `bucket_name` in `server`.
  """
  def create(server, bucket_name) do
    GenServer.call(server, {:create, bucket_name})
  end

  ## Server Callbacks
  def init(table) do
    names = :ets.new(table, [:named_table, read_concurrency: true])
    refs = %{}
    {:ok, {names, refs}}
  end

  def handle_call({:create, name}, _from, {names, refs}) do
    case lookup(names, name) do
      {:ok, pid} ->
        {:reply, pid, {names, refs}}

      :error ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            KeyValue.BucketSupervisor,
            KeyValue.Bucket
          )

        ref = Process.monitor(pid)
        refs = Map.put(refs, ref, name)
        :ets.insert(names, {name, pid})
        {:reply, pid, {names, refs}}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, {names, refs}) do
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(names, name)
    {:noreply, {names, refs}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
