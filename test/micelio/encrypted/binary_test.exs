defmodule Micelio.Encrypted.BinaryTest do
  use ExUnit.Case, async: false

  setup do
    previous_config = Application.get_env(:micelio, Micelio.Cloak)

    on_exit(fn ->
      if previous_config do
        Application.put_env(:micelio, Micelio.Cloak, previous_config)
      else
        Application.delete_env(:micelio, Micelio.Cloak)
      end
    end)

    :ok
  end

  test "supports decryption with previous cipher during key rotation" do
    old_key = <<1::256>>
    new_key = <<2::256>>

    Application.put_env(:micelio, Micelio.Cloak,
      json_library: Jason,
      ciphers: [
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V0", key: old_key}
      ]
    )

    assert {:ok, encrypted} = Micelio.Encrypted.Binary.dump("rotating-secret")

    Application.put_env(:micelio, Micelio.Cloak,
      json_library: Jason,
      ciphers: [
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: new_key},
        previous_1: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V0", key: old_key}
      ]
    )

    assert {:ok, "rotating-secret"} = Micelio.Encrypted.Binary.load(encrypted)
  end
end
