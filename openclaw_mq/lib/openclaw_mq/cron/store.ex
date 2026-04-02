defmodule OpenclawMq.Cron.Store do
  @moduledoc """
  ETS-backed store for cron entries. Persisted to DETS across restarts.

  Table name: `:cron_entries`

  Use `init/0` to create or reuse the ETS table. In production the application
  supervisor calls this automatically. During tests, `setup` blocks call
  `init/0` directly and then clear the table with `:ets.delete_all_objects/1`.
  """

  require Logger

  @table :cron_entries

  @doc "Initialise (or reuse) the ETS table and optionally load from DETS."
  @spec init() :: :ok
  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end

    load_from_dets()
    :ok
  end

  @doc "Store or overwrite a cron entry."
  @spec put(OpenclawMq.Cron.Entry.t()) :: :ok
  def put(%OpenclawMq.Cron.Entry{} = entry) do
    :ets.insert(@table, {entry.id, entry})
    sync_to_dets()
    :ok
  end

  @doc "Retrieve a cron entry by ID."
  @spec get(String.t()) :: {:ok, OpenclawMq.Cron.Entry.t()} | {:error, :not_found}
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, entry}] -> {:ok, entry}
      [] -> {:error, :not_found}
    end
  end

  @doc "Return all stored cron entries."
  @spec list() :: [OpenclawMq.Cron.Entry.t()]
  def list do
    :ets.tab2list(@table) |> Enum.map(fn {_id, entry} -> entry end)
  end

  @doc "Return all cron entries belonging to a specific agent."
  @spec list_for_agent(String.t()) :: [OpenclawMq.Cron.Entry.t()]
  def list_for_agent(agent_id) do
    list() |> Enum.filter(&(&1.agent_id == agent_id))
  end

  @doc """
  Update fields of an existing cron entry.

  Supported keys: `"enabled"`, `"last_fired_at"`.

  Returns `{:ok, updated_entry}` or `{:error, :not_found}`.
  """
  @spec update(String.t(), map()) :: {:ok, OpenclawMq.Cron.Entry.t()} | {:error, :not_found}
  def update(id, fields) do
    case get(id) do
      {:ok, entry} ->
        updated = apply_updates(entry, fields)
        :ets.insert(@table, {id, updated})
        sync_to_dets()
        {:ok, updated}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc "Delete a cron entry by ID."
  @spec delete(String.t()) :: :ok | {:error, :not_found}
  def delete(id) do
    case get(id) do
      {:ok, _} ->
        :ets.delete(@table, id)
        sync_to_dets()
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # --- Private helpers ---

  defp apply_updates(entry, fields) do
    Enum.reduce(fields, entry, fn {key, value}, acc ->
      case key do
        "enabled" -> %{acc | enabled: value}
        "last_fired_at" -> %{acc | last_fired_at: value}
        _ -> acc
      end
    end)
  end

  defp dets_path do
    Application.get_env(:openclaw_mq, :cron_dets_path, "priv/crons.dets")
  end

  defp dets_enabled? do
    Application.get_env(:openclaw_mq, :cron_dets_enabled, true)
  end

  defp load_from_dets do
    if dets_enabled?() do
      path = String.to_charlist(dets_path())

      case :dets.open_file(:cron_dets, file: path, type: :set) do
        {:ok, _ref} ->
          :dets.to_ets(:cron_dets, @table)
          :dets.close(:cron_dets)
          Logger.info("[Cron.Store] Loaded cron entries from DETS: #{dets_path()}")

        {:error, reason} ->
          Logger.warning("[Cron.Store] Could not open DETS at #{dets_path()}: #{inspect(reason)}")
      end
    end
  end

  defp sync_to_dets do
    if dets_enabled?() do
      path = String.to_charlist(dets_path())

      case :dets.open_file(:cron_dets, file: path, type: :set) do
        {:ok, _ref} ->
          :dets.from_ets(:cron_dets, @table)
          :dets.close(:cron_dets)

        {:error, reason} ->
          Logger.warning("[Cron.Store] Could not sync to DETS: #{inspect(reason)}")
      end
    end
  end
end
