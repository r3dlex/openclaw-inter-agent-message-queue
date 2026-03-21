defmodule OpenclawMq.Message do
  @moduledoc """
  Canonical message struct for inter-agent communication.
  """

  @enforce_keys [:id, :from, :to, :type, :subject, :body]
  defstruct [
    :id,
    :from,
    :to,
    :type,
    :subject,
    :body,
    :reply_to,
    :expires_at,
    priority: "NORMAL",
    status: "unread",
    created_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          from: String.t(),
          to: String.t(),
          priority: String.t(),
          type: String.t(),
          subject: String.t(),
          body: String.t(),
          reply_to: String.t() | nil,
          created_at: String.t(),
          expires_at: String.t() | nil,
          status: String.t()
        }

  @valid_priorities ~w(URGENT HIGH NORMAL LOW)
  @valid_types ~w(request response info error)
  @valid_statuses ~w(unread read acted archived)

  def new(attrs) when is_map(attrs) do
    msg = %__MODULE__{
      id: UUID.uuid4(),
      from: Map.fetch!(attrs, "from"),
      to: Map.fetch!(attrs, "to"),
      type: Map.get(attrs, "type", "info"),
      subject: Map.get(attrs, "subject", ""),
      body: Map.get(attrs, "body", ""),
      priority: Map.get(attrs, "priority", "NORMAL"),
      reply_to: Map.get(attrs, "replyTo"),
      expires_at: Map.get(attrs, "expiresAt"),
      status: "unread",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    with :ok <- validate_priority(msg.priority),
         :ok <- validate_type(msg.type) do
      {:ok, msg}
    end
  end

  @doc "Reconstruct a Message struct from a JSON-decoded map (for loading from disk)."
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      id: Map.fetch!(attrs, "id"),
      from: Map.fetch!(attrs, "from"),
      to: Map.fetch!(attrs, "to"),
      type: Map.get(attrs, "type", "info"),
      subject: Map.get(attrs, "subject", ""),
      body: Map.get(attrs, "body", ""),
      priority: Map.get(attrs, "priority", "NORMAL"),
      reply_to: Map.get(attrs, "replyTo"),
      expires_at: Map.get(attrs, "expiresAt"),
      status: Map.get(attrs, "status", "unread"),
      created_at: Map.get(attrs, "createdAt", DateTime.utc_now() |> DateTime.to_iso8601())
    }
  end

  def to_map(%__MODULE__{} = msg) do
    %{
      "id" => msg.id,
      "from" => msg.from,
      "to" => msg.to,
      "priority" => msg.priority,
      "type" => msg.type,
      "subject" => msg.subject,
      "body" => msg.body,
      "replyTo" => msg.reply_to,
      "createdAt" => msg.created_at,
      "expiresAt" => msg.expires_at,
      "status" => msg.status
    }
  end

  defp validate_priority(p) when p in @valid_priorities, do: :ok
  defp validate_priority(p), do: {:error, "invalid priority: #{p}"}

  defp validate_type(t) when t in @valid_types, do: :ok
  defp validate_type(t), do: {:error, "invalid type: #{t}"}
end
