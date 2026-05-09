defmodule OpenclawMq.Gateway.DeviceIdentity do
  @moduledoc """
  Ed25519 keypair management for OpenClaw gateway device attestation.

  Generates an Ed25519 keypair at runtime, persists it to
  ~/.openclaw/iamq-device-identity.json (atomic write: temp file + rename),
  and provides payload signing via :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519]).

  DeviceId is derived as SHA-256 of raw public key bytes → 64-char lowercase hex.
  Signature is Base64URL-encoded (no padding) DER.
  """

  @device_key_path Path.expand("~/.openclaw/iamq-device-identity.json")

  @doc """
  Load an existing keypair from disk, or generate a new one if none exists.
  Returns %{public_key: binary, private_key: binary, device_id: String.t}.
  """
  def load_or_generate_keypair do
    if File.exists?(@device_key_path) do
      load_keypair()
    else
      generate_keypair()
    end
  end

  @doc "Generate a new Ed25519 keypair, persist to disk, return identity map."
  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    device_id = derive_device_id(public_key)

    identity = %{
      public_key: public_key,
      private_key: private_key,
      device_id: device_id
    }

    persist_keypair(identity)
    identity
  end

  @doc "Sign a UTF-8 payload string. Returns Base64URL-encoded DER signature."
  def sign_payload(payload) when is_binary(payload) do
    %{private_key: private_key} = load_or_generate_keypair()
    der_sig = :crypto.sign(:eddsa, :none, payload, [private_key, :ed25519])
    Base.url_encode64(der_sig, padding: false)
  end

  # Derive deviceId: SHA-256 of raw public key bytes → 64-char lowercase hex
  defp derive_device_id(public_key) do
    hash = :crypto.hash(:sha256, public_key)
    Base.encode16(hash, case: :lower)
  end

  defp persist_keypair(%{public_key: pk, private_key: prk, device_id: did} = identity) do
    json =
      Jason.encode!(%{
        public_key: Base.url_encode64(pk, padding: false),
        private_key: Base.url_encode64(prk, padding: false),
        device_id: did
      })

    dir = Path.dirname(@device_key_path)
    File.mkdir_p(dir)

    tmp_path = @device_key_path <> ".tmp"
    File.write!(tmp_path, json)
    File.rename!(tmp_path, @device_key_path)

    identity
  end

  defp load_keypair do
    {:ok, json} = File.read(@device_key_path)
    map = Jason.decode!(json, keys: :atoms!)

    {:ok, public_key} = Base.url_decode64(map.public_key, padding: false)
    {:ok, private_key} = Base.url_decode64(map.private_key, padding: false)

    %{public_key: public_key, private_key: private_key, device_id: map.device_id}
  end
end
