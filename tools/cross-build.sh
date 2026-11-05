#!/bin/sh
# Builds a Bend program into a linux/arm64 binary.
#   tools/cross-build.sh main.bend out/main
# Emits C with the local bend, then compiles it in tools/cross (Docker), with
# the same flags bend uses for a CPU build.
set -eu
src=$1
out=$2
root=$(cd "$(dirname "$0")/.." && pwd)
img=mam-bend-cross
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bend "$src" -o "$tmp/main.c"
docker image inspect "$img" >/dev/null 2>&1 \
  || docker build -q -t "$img" "$root/tools/cross" >/dev/null
docker run --rm --platform linux/arm64 -v "$tmp:/src" "$img" \
  clang-14 -std=c11 -O3 main.c -lpthread -lm -o main
cp "$tmp/main" "$out"
echo "$out"
