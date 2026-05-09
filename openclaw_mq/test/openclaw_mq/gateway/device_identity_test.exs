defmodule OpenclawMq.Gateway.DeviceIdentityTest do
  use ExUnit.Case, async: false

  alias OpenclawMq.Gateway.DeviceIdentity

  # Use the real path — these tests just verify the module works
  # Cleanup is handled by the test suite setup

  describe "generate_keypair/0" do
    test "generates an Ed25519 keypair and persists to disk" do
      result = DeviceIdentity.generate_keypair()

      assert is_map(result)
      assert is_binary(result.public_key)
      assert is_binary(result.private_key)
      assert is_binary(result.device_id)
      assert byte_size(result.public_key) == 32
      assert byte_size(result.private_key) == 32
      assert String.length(result.device_id) == 64
      assert Regex.match?(~r/^[a-f0-9]{64}$/, result.device_id)
    end

    test "device_id is derived as SHA-256 of raw public key bytes" do
      %{public_key: pk, device_id: did} = DeviceIdentity.generate_keypair()
      hash = :crypto.hash(:sha256, pk)
      expected = Base.encode16(hash, case: :lower)
      assert did == expected
    end
  end

  describe "load_or_generate_keypair/0" do
    test "generates new keypair when none exists" do
      # Generates without error and returns identity map
      result = DeviceIdentity.load_or_generate_keypair()

      assert is_binary(result.public_key)
      assert is_binary(result.private_key)
      assert is_binary(result.device_id)
    end
  end

  describe "sign_payload/1" do
    test "returns Base64URL-encoded signature" do
      DeviceIdentity.generate_keypair()
      sig = DeviceIdentity.sign_payload("v3|test|payload|data")

      assert is_binary(sig)
      # Base64URL: no padding, url-safe chars
      assert sig =~ ~r"^[A-Za-z0-9_-]+$"
      refute sig =~ ~r"[+/=]"
    end

    test "signing same payload twice produces same signature (deterministic)" do
      DeviceIdentity.generate_keypair()
      sig1 = DeviceIdentity.sign_payload("v3|test|payload")
      sig2 = DeviceIdentity.sign_payload("v3|test|payload")
      assert sig1 == sig2
    end

    test "signing different payloads produces different signatures" do
      DeviceIdentity.generate_keypair()
      sig1 = DeviceIdentity.sign_payload("v3|test|payload|one")
      sig2 = DeviceIdentity.sign_payload("v3|test|payload|two")
      refute sig1 == sig2
    end
  end
end
