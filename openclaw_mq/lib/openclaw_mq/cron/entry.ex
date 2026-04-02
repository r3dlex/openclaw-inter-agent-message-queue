defmodule OpenclawMq.Cron.Entry do
  @moduledoc """
  Struct representing a registered cron schedule.

  Fields:
    * `:id` - UUID string, assigned by IAMQ on registration
    * `:agent_id` - the agent that owns this schedule
    * `:name` - logical name (used in the cron:: subject)
    * `:expression` - standard 5-field cron expression (UTC)
    * `:enabled` - boolean; disabled entries are stored but not fired
    * `:created_at` - DateTime
    * `:last_fired_at` - DateTime or nil
  """

  @enforce_keys [:id, :agent_id, :name, :expression]
  defstruct [:id, :agent_id, :name, :expression, :created_at, :last_fired_at, enabled: true]

  @type t :: %__MODULE__{
          id: String.t(),
          agent_id: String.t(),
          name: String.t(),
          expression: String.t(),
          enabled: boolean(),
          created_at: DateTime.t() | nil,
          last_fired_at: DateTime.t() | nil
        }

  @doc """
  Validate a 5-field cron expression string using the Crontab library parser.

  Returns `true` for valid expressions, `false` otherwise.
  """
  @spec valid_expression?(term()) :: boolean()
  def valid_expression?(nil), do: false
  def valid_expression?(""), do: false

  def valid_expression?(expr) when is_binary(expr) do
    case Crontab.CronExpression.Parser.parse(expr) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def valid_expression?(_), do: false

  @doc """
  Build an Entry from a map (e.g., HTTP body params).

  Returns `{:ok, %Entry{}}` or `{:error, reason}`.
  """
  @spec from_params(map()) :: {:ok, t()} | {:error, String.t()}
  def from_params(params) do
    with {:ok, agent_id} <- require_field(params, "agent_id"),
         {:ok, name} <- require_field(params, "name"),
         {:ok, expression} <- require_field(params, "expression"),
         true <-
           valid_expression?(expression) ||
             {:error, "invalid cron expression: #{inspect(expression)}"} do
      enabled = Map.get(params, "enabled", true)

      entry = %__MODULE__{
        id: UUID.uuid4(),
        agent_id: agent_id,
        name: name,
        expression: expression,
        enabled: enabled,
        created_at: DateTime.utc_now(),
        last_fired_at: nil
      }

      {:ok, entry}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Convert an Entry to a plain map for JSON serialization."
  @spec to_map(t()) :: map()
  def to_map(entry) do
    %{
      "id" => entry.id,
      "agent_id" => entry.agent_id,
      "name" => entry.name,
      "expression" => entry.expression,
      "enabled" => entry.enabled,
      "created_at" => datetime_to_string(entry.created_at),
      "last_fired_at" => datetime_to_string(entry.last_fired_at)
    }
  end

  # --- Private helpers ---

  defp require_field(params, key) do
    case Map.get(params, key) do
      nil -> {:error, "missing required field: #{key}"}
      "" -> {:error, "missing required field: #{key}"}
      value -> {:ok, value}
    end
  end

  defp datetime_to_string(nil), do: nil
  defp datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_to_string(other) when is_binary(other), do: other
end
