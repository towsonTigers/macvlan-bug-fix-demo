#!/usr/bin/env bash
# cleanup.sh — tears down both profiles, if running.
set -euo pipefail

sudo docker compose --profile buggy --profile fixed down --remove-orphans || true
echo "Cleanup complete."
