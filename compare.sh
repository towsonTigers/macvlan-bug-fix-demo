#!/usr/bin/env bash
# compare.sh — runs the buggy profile, shows the failure, tears it down, then
# runs the fixed profile and shows the success. Good for a live before/after demo.
set -euo pipefail
# shellcheck disable=SC1091
source .env

echo "#################################################"
echo "# PART 1 of 2: BUGGY (macvlan) — expect FAILURE  #"
echo "#################################################"
./run-buggy.sh
echo
echo "Tearing down buggy profile..."
sudo docker compose --profile buggy down

echo
echo "#################################################"
echo "# PART 2 of 2: FIXED (host network) — expect OK  #"
echo "#################################################"
./run-fixed.sh
echo
echo "Tearing down fixed profile..."
sudo docker compose --profile fixed down

echo
echo "Comparison complete. Same host, same handshake attempt — the only difference"
echo "was network_mode. That isolates network_mode as the cause and the fix."
