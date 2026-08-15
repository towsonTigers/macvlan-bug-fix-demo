#!/usr/bin/env bash
# run-fixed.sh — brings up the FIXED profile (host networking) and proves the
# handshake succeeds when both services are colocated on one Ubuntu host.
set -euo pipefail
# shellcheck disable=SC1091
source .env

echo "== Starting FIXED profile (network_mode: host) =="
sudo docker compose --env-file .env --profile fixed up -d --build

sleep 1
echo
echo "== Test 1: Docker host -> 'server-host' container, over localhost =="
if timeout 4 nc -zv 127.0.0.1 "${FIXED_PORT}"; then
  echo "RESULT: SUCCEEDED — host can reach the colocated service directly."
else
  echo "RESULT: FAILED — check that FIXED_PORT (${FIXED_PORT}) isn't already in use"
  echo "on the host: 'ss -tlnp | grep ${FIXED_PORT}'"
fi

echo
echo "== Test 2: 'client-host' container -> 'server-host' container, over localhost =="
if sudo docker exec client-host timeout 4 nc -zv 127.0.0.1 "${FIXED_PORT}"; then
  echo "RESULT: SUCCEEDED — container-to-container handshake works too, since both"
  echo "share the host's network namespace directly (no macvlan boundary to cross)."
else
  echo "RESULT: FAILED — this would be unexpected for host networking; check FIXED_PORT."
fi

echo
echo "Tear down with: sudo docker compose --profile fixed down"
