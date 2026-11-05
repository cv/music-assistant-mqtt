#!/bin/sh
# Builds a Bend program into one static linux/arm64 binary (musl, by zig in Docker), for running
# tests on a Linux host; the image (Dockerfile) builds the program the same way.
#   tools/cross-build.sh main.bend out/main [aarch64|x86_64]
set -eu
src=$1
out=$2
arch=${3:-aarch64}
mkdir -p "$(dirname "$out")"
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
# Under the home directory: Docker Desktop shares it, not /tmp.
mkdir -p "$HOME/.cache"
tmp=$(mktemp -d "$HOME/.cache/mam-build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
bend "$src" -o "$tmp/main.c"
docker run --rm -v "$tmp:/src" -e ZIG_GLOBAL_CACHE_DIR=/tmp/zig -e ZIG_LOCAL_CACHE_DIR=/tmp/zig \
  alpine:3.22 sh -c "apk add -q zig >/dev/null && cd /tmp && cp /src/main.c . &&
    zig cc -target $arch-linux-musl -O3 -static -s -o /src/main main.c -lpthread -lm"
cp "$tmp/main" "$out"
echo "$out"
