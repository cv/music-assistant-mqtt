#!/bin/sh
# Builds the bridge for linux/arm64 and runs it on HOST (over ssh) with Docker Compose, in
# ~/music-assistant-mqtt: the binary, deploy/Dockerfile and (the first time) deploy/compose.yaml.
# The config (music-assistant-mqtt.conf, 0600) must be there already.
#
#   tools/deploy.sh HOST
set -eu
host=$1
dir=music-assistant-mqtt
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
bend PROOF.bend | grep -q "ALL PROOFS CHECK" || { echo "the proofs don't check" >&2; exit 1; }
tools/cross-build.sh mam.bend out/mam >/dev/null
ssh "$host" "mkdir -p $dir/data && test -f $dir/music-assistant-mqtt.conf" \
  || { echo "write $host:$dir/music-assistant-mqtt.conf first (deploy/music-assistant-mqtt.conf.example)" >&2; exit 1; }
scp -q out/mam deploy/Dockerfile "$host:$dir/"
ssh "$host" "test -f $dir/compose.yaml" || scp -q deploy/compose.yaml "$host:$dir/"
ssh "$host" "cd $dir && docker compose build -q && docker compose up -d && sleep 5 && docker compose logs --tail 20"
