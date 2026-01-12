defmodule Micelio.Sessions.ConflictTest do
  use ExUnit.Case, async: true

  alias Micelio.Sessions.Conflict

  describe "build_filter/2" do
    test "creates a compact bloom filter for file paths" do
      filter = Conflict.build_filter(["lib/a.ex", "lib/b.ex"], size: 64, hash_count: 3)

      assert filter["size"] == 64
      assert filter["hash_count"] == 3
      assert is_binary(filter["bits"])
    end
  end

  describe "might_conflict?/2" do
    test "returns true for paths that were added" do
      filter = Conflict.build_filter(["lib/a.ex", "lib/b.ex"], size: 64, hash_count: 3)

      assert Conflict.might_conflict?(filter, "lib/a.ex")
      assert Conflict.might_conflict?(filter, "lib/b.ex")
    end

    test "returns false for paths that are definitely not present" do
      filter = Conflict.build_filter(["lib/a.ex"], size: 64, hash_count: 3)

      refute Conflict.might_conflict?(filter, "priv/static/logo.png")
    end
  end
end
