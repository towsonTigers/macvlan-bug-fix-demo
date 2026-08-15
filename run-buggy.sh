#!/usr/bin/env bash
# run-buggy.sh — brings up the macvlan (colocated-failure) profile, for comparison.
set -euo pipefail
# shellcheck disable=SC1091
source .env

echo "== Starting BUGGY profile (macvlan) =="
sudo docker compose --env-file .env --profile buggy up -d --build

sleep 1
echo
echo "== Testing host -> container over macvlan (expected: FAIL) =="
if timeout 4 nc -zv "${SERVER_IP}" 5000; then
  echo "RESULT: succeeded (unexpected on a real macvlan setup)"
else
  echo "RESULT: FAILED as expected — this is the bug being fixed below."
fi

echo
echo "Tear down with: sudo docker compose --profile buggy down"
