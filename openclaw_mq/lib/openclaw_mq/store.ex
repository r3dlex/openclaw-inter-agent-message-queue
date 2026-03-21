defmodule OpenclawMq.Store do
  @moduledoc """
  ETS-backed message store with file-based persistence.

  Messages are stored in ETS for fast access and simultaneously written
  to `queue/{agent_id}/` as JSON files. On startup, existing messages
  are loaded from disk, so nothing is lost on restart.

  File naming: `{ISO-timestamp}-{from_agent}.json` (colons replaced with dashes).
  """
  use GenServer

  require Logger

  @table :openclaw_mq_messages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Store a message, persist to disk, and publish to PubSub."
  def put(%OpenclawMq.Message{} = msg) do
    :ets.insert(@table, {msg.id, msg})

    # Persist to disk
    persist_to_disk(msg)

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

  @doc "Update the status of a message (also updates the file on disk)."
  def update_status(id, new_status) when new_status in ~w(unread read acted archived) do
    case get(id) do
      {:ok, msg} ->
        updated = %{msg | status: new_status}
        :ets.insert(@table, {id, updated})
        persist_to_disk(updated)
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
    |> Enum.each(fn {id, msg} ->
      :ets.delete(@table, id)
      delete_from_disk(msg)
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
    |> Enum.each(fn {id, msg} ->
      :ets.delete(@table, id)
      delete_from_disk(msg)
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
    loaded = load_from_disk()
    Logger.info("[Store] Loaded #{loaded} persisted messages from disk")
    {:ok, %{}}
  end

  # --- Disk persistence ---

  defp queue_dir do
    Application.get_env(:openclaw_mq, :queue_dir, "queue")
  end

  defp agent_dir(agent_id) do
    Path.join(queue_dir(), agent_id)
  end

  defp message_filename(msg) do
    ts = String.replace(msg.created_at, ":", "-")
    "#{ts}-#{msg.from}.json"
  end

  defp message_filepath(msg) do
    Path.join(agent_dir(msg.to), message_filename(msg))
  end

  defp persist_to_disk(msg) do
    dir = agent_dir(msg.to)
    File.mkdir_p!(dir)
    path = message_filepath(msg)
    json = Jason.encode!(OpenclawMq.Message.to_map(msg), pretty: true)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} ->
        Logger.warning("[Store] Failed to persist #{msg.id} to #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp delete_from_disk(msg) do
    path = message_filepath(msg)

    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} ->
        Logger.warning("[Store] Failed to delete #{path}: #{inspect(reason)}")
    end
  end

  defp load_from_disk do
    dir = queue_dir()

    unless File.dir?(dir) do
      Logger.info("[Store] Queue directory #{dir} not found, starting empty")
      0
    else
      dir
      |> File.ls!()
      |> Enum.filter(fn entry -> File.dir?(Path.join(dir, entry)) end)
      |> Enum.flat_map(fn agent_dir_name ->
        agent_path = Path.join(dir, agent_dir_name)
        load_agent_messages(agent_path)
      end)
      |> length()
    end
  end

  defp load_agent_messages(agent_path) do
    case File.ls(agent_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.flat_map(fn filename ->
          filepath = Path.join(agent_path, filename)
          load_message_file(filepath)
        end)

      {:error, _} ->
        []
    end
  end

  defp load_message_file(filepath) do
    case File.read(filepath) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, attrs} when is_map(attrs) ->
            msg = OpenclawMq.Message.from_map(attrs)
            :ets.insert(@table, {msg.id, msg})
            [msg]

          {:error, reason} ->
            Logger.warning("[Store] Skipping invalid JSON #{filepath}: #{inspect(reason)}")
            []
        end

      {:error, reason} ->
        Logger.warning("[Store] Failed to read #{filepath}: #{inspect(reason)}")
        []
    end
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
