defmodule Micelio.Encrypted.BinaryTest do
  use ExUnit.Case, async: false

  test "supports decryption with previous cipher during key rotation" do
    previous_config = Application.get_env(:micelio, Micelio.Cloak)

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
  after
    Application.put_env(:micelio, Micelio.Cloak, previous_config)
  end
end
