#!/usr/bin/env bash
# =============================================================================
# wait-for-it.sh — Wait for a TCP host:port to become reachable
# =============================================================================
# Usage:
#   ./wait-for-it.sh <host> <port> [--timeout=<seconds>]
#
# Blocks until a TCP connection can be established to <host>:<port>, or until
# the timeout is exceeded. Exits 0 on success, 1 on timeout.
#
# This is used by the openhim-setup container to wait for the OpenHIM Core
# API to become available before attempting to seed configuration.
# =============================================================================

set -euo pipefail

# ---- Argument Parsing -------------------------------------------------------
HOST="${1:?Error: HOST argument is required (e.g. openhim-core)}"
PORT="${2:?Error: PORT argument is required (e.g. 8080)}"
TIMEOUT=60  # Default timeout in seconds

# Parse optional flags
shift 2
for arg in "$@"; do
  case "$arg" in
    --timeout=*)
      TIMEOUT="${arg#*=}"
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

# ---- Wait Loop --------------------------------------------------------------
echo "[wait-for-it] Waiting for ${HOST}:${PORT} (timeout: ${TIMEOUT}s)..."

elapsed=0
interval=2

while [ "$elapsed" -lt "$TIMEOUT" ]; do
  # Attempt a TCP connection using /dev/tcp or nc (netcat)
  if nc -z "$HOST" "$PORT" 2>/dev/null; then
    echo "[wait-for-it] ✓ ${HOST}:${PORT} is reachable after ${elapsed}s."
    exit 0
  fi

  sleep "$interval"
  elapsed=$((elapsed + interval))
done

# ---- Timeout -----------------------------------------------------------------
echo "[wait-for-it] ✗ Timeout after ${TIMEOUT}s waiting for ${HOST}:${PORT}."
exit 1
