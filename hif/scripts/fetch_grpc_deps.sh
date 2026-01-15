#!/bin/sh
set -eu

grpc_root="$(cd "$(dirname "$0")/.." && pwd)/vendor/grpc"

required_paths="
third_party/abseil-cpp
third_party/boringssl-with-bazel
third_party/cares/cares
third_party/protobuf
third_party/re2
third_party/zlib
"

cd "$grpc_root"

submodule_url() {
  git config -f .gitmodules --get "submodule.$1.url"
}

submodule_commit() {
  awk -v p="$1" '$1 == p { print $2 }' "$grpc_root/tools/run_tests/sanity/check_submodules.sh"
}

for path in $required_paths; do
  if [ -d "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ]; then
    continue
  fi

  url="$(submodule_url "$path")"
  commit="$(submodule_commit "$path")"

  if [ -z "$url" ] || [ -z "$commit" ]; then
    echo "missing submodule metadata for $path" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$path")"
  rm -rf "$path"
  git clone "$url" "$path"
  git -C "$path" fetch --depth 1 origin "$commit"
  git -C "$path" checkout "$commit"
done
