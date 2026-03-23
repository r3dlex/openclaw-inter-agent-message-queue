defmodule OpenclawMq do
  @moduledoc """
  OpenClaw MQ - Inter-agent message queue with real-time pub/sub.

  ## Architecture

  - Phoenix.PubSub for in-process topic routing
  - ETS-backed message store
  - HTTP API (port 18790) for agents to send/receive via curl
  - WebSocket server (port 18793) for real-time push
  - OpenClaw gateway RPC + CLI fallback for triggering agents

  ## Quick Start

      # Register
      curl -X POST http://127.0.0.1:18790/register -H 'Content-Type: application/json' \\
        -d '{"agent_id": "mail_agent"}'

      # Send a message
      curl -X POST http://127.0.0.1:18790/send -H 'Content-Type: application/json' \\
        -d '{"from":"mail_agent","to":"librarian_agent","type":"request","subject":"Research X","body":"Details..."}'

      # Check inbox
      curl http://127.0.0.1:18790/inbox/librarian_agent?status=unread

      # Ack a message
      curl -X PATCH http://127.0.0.1:18790/messages/MSG_ID -H 'Content-Type: application/json' \\
        -d '{"status":"read"}'

      # Queue status
      curl http://127.0.0.1:18790/status
  """
end
