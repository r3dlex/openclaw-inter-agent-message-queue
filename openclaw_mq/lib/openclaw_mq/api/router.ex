defmodule OpenclawMq.Api.Router do
  @moduledoc """
  HTTP API for agents to interact with the message queue.

  Endpoints:
    POST   /register            - Register an agent (with optional metadata)
    POST   /heartbeat           - Agent heartbeat
    POST   /send                - Send a message (direct or broadcast)
    GET    /inbox/:agent_id     - Get inbox for an agent
    PATCH  /messages/:id        - Update message status
    POST   /callback            - Register a callback URL for push delivery
    DELETE /callback            - Remove a callback URL
    GET    /status              - Queue health summary
    GET    /agents              - List all registered agents (with metadata)
    GET    /agents/:agent_id    - Get a single agent's profile
    PUT    /agents/:agent_id    - Update an agent's metadata
  """
  use Plug.Router

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  # Register an agent (with optional metadata)
  post "/register" do
    %{"agent_id" => agent_id} = conn.body_params
    metadata = Map.drop(conn.body_params, ["agent_id"])
    :ok = OpenclawMq.Registry.register(agent_id, metadata)
    send_json(conn, 200, %{"status" => "registered", "agent_id" => agent_id})
  end

  # Agent heartbeat
  post "/heartbeat" do
    %{"agent_id" => agent_id} = conn.body_params
    :ok = OpenclawMq.Registry.heartbeat(agent_id)
    send_json(conn, 200, %{"status" => "ok"})
  end

  # Send a message
  post "/send" do
    case OpenclawMq.Message.new(conn.body_params) do
      {:ok, msg} ->
        :ok = OpenclawMq.Store.put(msg)

        # Trigger delivery to the target agent
        unless msg.to == "broadcast" do
          OpenclawMq.Gateway.Dispatcher.deliver(msg.to, msg)
        else
          # For broadcasts, trigger all registered agents
          for %{"id" => agent_id} <- OpenclawMq.Registry.list_agents() do
            if agent_id != msg.from do
              OpenclawMq.Gateway.Dispatcher.deliver(agent_id, msg)
            end
          end
        end

        send_json(conn, 201, OpenclawMq.Message.to_map(msg))

      {:error, reason} ->
        send_json(conn, 400, %{"error" => reason})
    end
  end

  # Get inbox for an agent
  get "/inbox/:agent_id" do
    status_filter = conn.params["status"]
    messages = OpenclawMq.Store.inbox(agent_id, status_filter)
    send_json(conn, 200, %{"messages" => Enum.map(messages, &OpenclawMq.Message.to_map/1)})
  end

  # Update message status
  patch "/messages/:id" do
    %{"status" => new_status} = conn.body_params

    case OpenclawMq.Store.update_status(id, new_status) do
      :ok ->
        send_json(conn, 200, %{"status" => "updated"})

      {:error, reason} ->
        send_json(conn, 404, %{"error" => reason})
    end
  end

  # Queue health summary
  get "/status" do
    summary = OpenclawMq.Store.status_summary()
    agents = OpenclawMq.Registry.list_agents()

    send_json(conn, 200, %{
      "checkedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "queues" => summary,
      "agents_online" => agents
    })
  end

  # Register a callback URL for push delivery
  post "/callback" do
    %{"agent_id" => agent_id, "url" => url} = conn.body_params
    :ok = OpenclawMq.Gateway.Dispatcher.register_callback(agent_id, url)

    send_json(conn, 200, %{
      "status" => "callback_registered",
      "agent_id" => agent_id,
      "url" => url
    })
  end

  # Remove a callback URL
  delete "/callback" do
    %{"agent_id" => agent_id} = conn.body_params
    :ok = OpenclawMq.Gateway.Dispatcher.unregister_callback(agent_id)
    send_json(conn, 200, %{"status" => "callback_removed", "agent_id" => agent_id})
  end

  # List registered agents (with metadata)
  get "/agents" do
    agents = OpenclawMq.Registry.list_agents()
    send_json(conn, 200, %{"agents" => agents})
  end

  # Get a single agent's profile
  get "/agents/:agent_id" do
    case OpenclawMq.Registry.get_agent(agent_id) do
      {:ok, agent} ->
        send_json(conn, 200, agent)

      {:error, _} ->
        send_json(conn, 404, %{"error" => "agent not found"})
    end
  end

  # Update an agent's metadata
  put "/agents/:agent_id" do
    case OpenclawMq.Registry.update_metadata(agent_id, conn.body_params) do
      :ok ->
        {:ok, agent} = OpenclawMq.Registry.get_agent(agent_id)
        send_json(conn, 200, agent)

      {:error, reason} ->
        send_json(conn, 404, %{"error" => reason})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not found"})
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
