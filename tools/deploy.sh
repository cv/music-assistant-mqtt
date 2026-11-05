#!/bin/sh
# Runs a release image (ghcr.io/cv/music-assistant-mqtt:VERSION, built by CI) on HOST over ssh with
# Docker Compose, in ~/music-assistant-mqtt (deploy/compose.yaml with that version; a compose.yaml
# already there is replaced). The config (music-assistant-mqtt.conf, 0600) must be there already.
#
#   tools/deploy.sh HOST VERSION      e.g. tools/deploy.sh myhost 0.1.0
set -eu
host=$1
version=$2
dir=music-assistant-mqtt
root=$(cd "$(dirname "$0")/.." && pwd)
ssh "$host" "mkdir -p $dir/data && test -f $dir/music-assistant-mqtt.conf" \
  || { echo "write $host:$dir/music-assistant-mqtt.conf first (deploy/music-assistant-mqtt.conf.example)" >&2; exit 1; }
sed "s/@VERSION@/$version/" "$root/deploy/compose.yaml" | ssh "$host" "cat > $dir/compose.yaml"
ssh "$host" "cd $dir && rm -f mam Dockerfile && docker compose pull -q && docker compose up -d && sleep 5 && docker compose logs --tail 20"
