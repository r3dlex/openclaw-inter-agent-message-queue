defmodule OpenclawMqTest do
  use ExUnit.Case

  test "message creation with valid attrs" do
    attrs = %{
      "from" => "mail_agent",
      "to" => "librarian_agent",
      "type" => "request",
      "subject" => "Test message",
      "body" => "Hello from tests",
      "priority" => "HIGH"
    }

    assert {:ok, msg} = OpenclawMq.Message.new(attrs)
    assert msg.from == "mail_agent"
    assert msg.to == "librarian_agent"
    assert msg.priority == "HIGH"
    assert msg.status == "unread"
    assert msg.id != nil
  end

  test "message creation rejects invalid priority" do
    attrs = %{
      "from" => "a",
      "to" => "b",
      "type" => "info",
      "subject" => "x",
      "body" => "y",
      "priority" => "INVALID"
    }

    assert {:error, _} = OpenclawMq.Message.new(attrs)
  end

  test "message creation rejects invalid type" do
    attrs = %{
      "from" => "a",
      "to" => "b",
      "type" => "banana",
      "subject" => "x",
      "body" => "y"
    }

    assert {:error, _} = OpenclawMq.Message.new(attrs)
  end

  test "message to_map roundtrip" do
    attrs = %{
      "from" => "sysadmin_agent",
      "to" => "broadcast",
      "type" => "info",
      "subject" => "System notice",
      "body" => "All clear"
    }

    {:ok, msg} = OpenclawMq.Message.new(attrs)
    map = OpenclawMq.Message.to_map(msg)

    assert map["from"] == "sysadmin_agent"
    assert map["to"] == "broadcast"
    assert map["status"] == "unread"
    assert is_binary(map["id"])
    assert is_binary(map["createdAt"])
  end
end
