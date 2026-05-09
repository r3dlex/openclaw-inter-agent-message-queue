defmodule OpenclawMq.Gateway.RpcClient do
  @moduledoc """
  Ephemeral WebSocket client for sending a single RPC message
  to the OpenClaw gateway, then disconnecting.

  State machine:
    :idle → :waiting_challenge → :authenticated → :closing → :done

  Handles the challenge-response handshake, then issues gateway.send RPC.
  """
  use WebSockex

  require Logger

  # Client identity
  @client_id "gateway-client"
  @client_version "1.0.0"
  @platform "elixir"
  @client_mode "node"
  @device_family "server"

  # --- Client initialization ---

  def start_link({gateway_url, token, delivery_payload, caller}) do
    state = %{
      gateway_url: gateway_url,
      token: token,
      delivery_payload: delivery_payload,
      caller: caller,
      req_id: 1,
      status: :idle
    }

    WebSockex.start_link(gateway_url, __MODULE__, state, name: __MODULE__)
  end

  # --- State machine: idle → waiting_challenge → authenticated → closing → done ---

  @impl true
  def handle_connect(_conn, state) do
    Logger.debug("[RpcClient] Connected to gateway, waiting for challenge...")
    {:ok, %{state | status: :waiting_challenge}}
  end

  @impl true
  def handle_frame({:text, frame}, state) do
    case Jason.decode(frame) do
      {:ok, %{"type" => "event", "event" => "connect.challenge", "payload" => payload}} ->
        handle_challenge(payload, state)

      {:ok, %{"type" => "res", "id" => id, "ok" => true, "payload" => payload}} ->
        handle_auth_response(id, payload, state)

      {:ok, %{"type" => "res", "id" => _id, "ok" => false, "payload" => payload}} ->
        send(state.caller, {:rpc_result, {:error, payload}})
        {:close, %{state | status: :closing}}

      {:ok, %{"type" => "event", "event" => event}} ->
        Logger.warning("[RpcClient] Unexpected event #{event}, ignoring")
        {:ok, state}

      _ ->
        Logger.warning("[RpcClient] Unexpected frame: #{frame}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame(_frame, state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    {:ok, %{state | status: :done}}
  end

  # --- Challenge handling ---

  defp handle_challenge(%{"nonce" => nonce, "ts" => _ts}, state) do
    Logger.debug("[RpcClient] Received connect.challenge with nonce=#{nonce}")

    # Load system device identity from ~/.openclaw/identity/device.json
    identity = load_iamq_or_system_device_identity()

    # Build device auth payload (pipe-delimited, v3 format)
    signed_at_ms = System.system_time(:millisecond)
    scopes = []

    device_auth_payload = build_device_auth_payload_v3(%{
      device_id: identity["deviceId"],
      client_id: @client_id,
      client_mode: @client_mode,
      role: "node",
      scopes: scopes,
      signed_at_ms: signed_at_ms,
      token: state.token,
      nonce: nonce,
      platform: @platform,
      device_family: @device_family
    })

    # DEBUG: Log exact payload bytes for signature verification comparison
    payload_bytes = :erlang.iolist_to_binary(device_auth_payload)
    priv_key_bytes = identity["private_key"]
    signature = :crypto.sign(:eddsa, :none, device_auth_payload, [priv_key_bytes, :ed25519])
    signature_b64 = Base.url_encode64(signature, padding: false)

    Logger.debug("[RpcClient] DEBUG SIGNING: " <>
      "payload_size=#{byte_size(payload_bytes)} " <>
      "payload_hex=#{Base.encode16(payload_bytes, case: :lower)} " <>
      "priv_key_size=#{byte_size(priv_key_bytes)} " <>
      "priv_key_hex=#{Base.encode16(priv_key_bytes, case: :lower)} " <>
      "signature_size=#{byte_size(signature)} " <>
      "signature_hex=#{Base.encode16(signature, case: :lower)}")

    # Build connect.req RPC request
    connect_req = %{
      "type" => "req",
      "id" => Integer.to_string(state.req_id),
      "method" => "connect",
      "params" => %{
        "minProtocol" => 3,
        "maxProtocol" => 3,
        "client" => %{
          "id" => @client_id,
          "version" => @client_version,
          "platform" => @platform,
          "mode" => @client_mode
        },
        "role" => "node",
        "scopes" => scopes,
        "auth" => %{
          "token" => state.token
        },
        "device" => %{
          "id" => identity["deviceId"],
          "nonce" => nonce,
          "publicKey" => Base.url_encode64(identity["public_key"], padding: false),
          "signature" => signature_b64,
          "signedAt" => signed_at_ms
        }
      }
    }

    Logger.debug("[RpcClient] Sending connect.req: #{inspect(connect_req, pretty: true)}")
    {:reply, {:text, Jason.encode!(connect_req)}, %{state | req_id: state.req_id + 1}}
  end

  # --- Auth response handling ---

  defp handle_auth_response(_id, %{"type" => "hello-ok", "protocol" => 3}, state) do
    Logger.info("[RpcClient] Authentication successful (protocol 3)")

    # Now send the delivery RPC
    %{account: account, channel: channel, content: content, deliver: deliver} =
      state.delivery_payload

    # André's Telegram chat ID — used as the target for all Telegram deliveries
    andre_telegram_id = "5887382088"

    send_req = %{
      "type" => "req",
      "id" => Integer.to_string(state.req_id),
      "method" => "gateway.send",
      "params" => %{
        "account" => account,
        "channel" => channel,
        "content" => content,
        "deliver" => deliver,
        "target" => andre_telegram_id
      }
    }

    Logger.debug("[RpcClient] Sending gateway.send RPC")
    {:reply, {:text, Jason.encode!(send_req)}, %{state | req_id: state.req_id + 1, status: :authenticated}}
  end

  defp handle_auth_response(id, payload, state) do
    Logger.warning("[RpcClient] Unexpected auth response id=#{id} payload=#{inspect(payload)}")
    send(state.caller, {:rpc_result, {:error, "unexpected auth response"}})
    {:close, %{state | status: :closing}}
  end

  # --- Device auth payload builder (matches OpenClaw gateway v3 format) ---
  # Payload format: "v3|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce|platform|deviceFamily"

  defp build_device_auth_payload_v3(params) do
    scopes_str = Enum.join(params.scopes, ",")

    [
      "v3",
      params.device_id,
      params.client_id,
      params.client_mode,
      params.role,
      scopes_str,
      Integer.to_string(params.signed_at_ms),
      params.token || "",
      params.nonce,
      params.platform,
      params.device_family
    ]
    |> Enum.join("|")
  end

  # --- IAMQ device identity (prioritized) or system device fallback ---

  # Try IAMQ-specific identity first (was paired with gateway), fall back to system device.json
  defp load_iamq_or_system_device_identity do
    iamq_path = Path.expand("~/.openclaw/iamq-device-identity.json")

    if File.exists?(iamq_path) do
      Logger.debug("[RpcClient] Loading IAMQ device identity from: #{iamq_path}")
      load_iamq_device_identity(iamq_path)
    else
      Logger.debug("[RpcClient] No IAMQ identity at #{iamq_path} — loading system device")
      load_system_device_identity(Path.expand("~/.openclaw/identity/device.json"))
    end
  rescue
    e ->
      Logger.warning("[RpcClient] Failed to load IAMQ identity: #{inspect(e)} — falling back to system device")
      load_system_device_identity(Path.expand("~/.openclaw/identity/device.json"))
  end

  # Load system device identity (PKCS#8 PEM format) from device.json
  defp load_system_device_identity(path) do
    Logger.debug("[RpcClient] Loading system device identity from: #{path}")
    {:ok, body} = File.read(path)
    {:ok, json} = Jason.decode(body)
    private_key = decode_pem_private_key(json["privateKeyPem"])
    public_key = decode_pem_public_key(json["publicKeyPem"])
    Logger.debug("[RpcClient] Identity loaded, deviceId=#{json["deviceId"]}")
    Map.merge(json, %{"private_key" => private_key, "public_key" => public_key})
  rescue
    e ->
      Logger.error("[RpcClient] Failed to load system device identity: #{inspect(e)}")
      raise e
  end

  # Load IAMQ-specific identity (base64-encoded raw Ed25519 bytes, pre-paired with gateway)
  defp load_iamq_device_identity(path) do
    {:ok, body} = File.read(path)
    {:ok, json} = Jason.decode(body)
    {:ok, private_key} = Base.url_decode64(Map.get(json, "private_key"), padding: false)
    {:ok, public_key} = Base.url_decode64(Map.get(json, "public_key"), padding: false)
    device_id = Map.get(json, "device_id")
    Logger.debug("[RpcClient] IAMQ identity loaded: deviceId=#{device_id}")
    %{"deviceId" => device_id, "private_key" => private_key, "public_key" => public_key}
  end

  # Decode Ed25519 private key from PEM (uses pem_entry_decode for direct ECPrivateKey format)
  defp decode_pem_private_key(pem_string) do
    [pem_entry] = :public_key.pem_decode(pem_string)
    {:ECPrivateKey, _version, priv_bytes, _curve, :asn1_NOVALUE, :asn1_NOVALUE} =
      :public_key.pem_entry_decode(pem_entry)
    priv_bytes
  end

  # Decode Ed25519 public key from PEM
  defp decode_pem_public_key(pem_string) do
    [pem_entry] = :public_key.pem_decode(pem_string)
    {{:ECPoint, pub_bytes}, {:namedCurve, _oid}} = :public_key.pem_entry_decode(pem_entry)
    pub_bytes
  end
end
