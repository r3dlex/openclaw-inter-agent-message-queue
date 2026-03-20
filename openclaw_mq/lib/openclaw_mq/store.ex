defmodule OpenclawMq.Store do
  @moduledoc """
  ETS-backed message store. Messages are keyed by ID.
  Provides inbox queries per agent and broadcast.
  """
  use GenServer

  require Logger

  @table :openclaw_mq_messages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store a message and publish to PubSub."
  def put(%OpenclawMq.Message{} = msg) do
    :ets.insert(@table, {msg.id, msg})

    topic =
      case msg.to do
        "broadcast" -> "broadcast"
        agent_id -> "agent:#{agent_id}"
      end

    Phoenix.PubSub.broadcast(OpenclawMq.PubSub, topic, {:new_message, msg})
    Logger.info("[Store] Message #{msg.id} from=#{msg.from} to=#{msg.to} subject=#{msg.subject}")
    :ok
  end

  @doc "Get a message by ID."
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, msg}] -> {:ok, msg}
      [] -> :not_found
    end
  end

  @doc "Get all messages for a given agent (direct + broadcast), optionally filtered by status."
  def inbox(agent_id, status_filter \\ nil) do
    :ets.tab2list(@table)
    |> Enum.map(fn {_id, msg} -> msg end)
    |> Enum.filter(fn msg ->
      (msg.to == agent_id or msg.to == "broadcast") and
        (status_filter == nil or msg.status == status_filter)
    end)
    |> Enum.sort_by(& &1.created_at)
  end

  @doc "Update the status of a message."
  def update_status(id, new_status) when new_status in ~w(unread read acted archived) do
    case get(id) do
      {:ok, msg} ->
        updated = %{msg | status: new_status}
        :ets.insert(@table, {id, updated})
        :ok

      :not_found ->
        {:error, "message not found: #{id}"}
    end
  end

  @doc "Delete messages with status 'acted' or 'archived' older than max_age_ms."
  def purge_old(max_age_ms) do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, msg} ->
      msg.status in ["acted", "archived"] and
        message_age_ms(msg, now) > max_age_ms
    end)
    |> Enum.each(fn {id, _msg} ->
      :ets.delete(@table, id)
      Logger.info("[Store] Purged old message: #{id}")
    end)
  end

  @doc "Delete expired messages (past expiresAt)."
  def purge_expired do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, msg} ->
      msg.expires_at != nil and expired?(msg.expires_at, now)
    end)
    |> Enum.each(fn {id, _msg} ->
      :ets.delete(@table, id)
      Logger.info("[Store] Purged expired message: #{id}")
    end)
  end

  @doc "Return a status summary of all queues."
  def status_summary do
    messages = :ets.tab2list(@table) |> Enum.map(fn {_id, msg} -> msg end)

    messages
    |> Enum.group_by(& &1.to)
    |> Enum.map(fn {agent, msgs} ->
      unread = Enum.count(msgs, &(&1.status == "unread"))
      read = Enum.count(msgs, &(&1.status == "read"))
      acted = Enum.count(msgs, &(&1.status == "acted"))

      oldest_unread =
        msgs
        |> Enum.filter(&(&1.status == "unread"))
        |> Enum.min_by(& &1.created_at, fn -> nil end)

      {agent,
       %{
         "unread" => unread,
         "read" => read,
         "acted" => acted,
         "oldest_unread" => if(oldest_unread, do: oldest_unread.created_at, else: nil)
       }}
    end)
    |> Map.new()
  end

  # Server

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  defp message_age_ms(msg, now) do
    case DateTime.from_iso8601(msg.created_at) do
      {:ok, created, _} -> DateTime.diff(now, created, :millisecond)
      _ -> 0
    end
  end

  defp expired?(expires_at, now) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, exp, _} -> DateTime.compare(now, exp) == :gt
      _ -> false
    end
  end
end
