#!/usr/bin/env bash
# =============================================================================
# init-openhim.sh — Seed OpenHIM with channel & client configuration
# =============================================================================
# This script authenticates against the OpenHIM Core API and pushes the
# channel and client definitions stored in /config/*.json. It is designed
# to run inside the ephemeral `openhim-setup` container.
#
# Environment variables (set via docker-compose.yml):
#   OPENHIM_API_URL        — Base URL of the OpenHIM API (default: https://openhim-core:8080)
#   OPENHIM_ROOT_EMAIL     — Admin email      (default: root@openhim.org)
#   OPENHIM_ROOT_PASSWORD  — Admin password    (default: openhim-password)
#
# Exit codes:
#   0  — All configuration seeded successfully
#   1  — One or more API calls failed
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
API_URL="${OPENHIM_API_URL:-https://openhim-core:8080}"
EMAIL="${OPENHIM_ROOT_EMAIL:-root@openhim.org}"
PASSWORD="${OPENHIM_ROOT_PASSWORD:-openhim-password}"

CHANNELS_FILE="/config/channels.json"
CLIENTS_FILE="/config/clients.json"

# Curl options: silent, insecure (self-signed cert), show errors, fail on HTTP errors
CURL_OPTS="-sSk --fail --max-time 30"

# Track overall success
EXIT_CODE=0

# =============================================================================
# Helper Functions
# =============================================================================

# ---- Logging helpers --------------------------------------------------------
info()  { echo "[init-openhim] ℹ $*" >&2; }
ok()    { echo "[init-openhim] ✓ $*" >&2; }
warn()  { echo "[init-openhim] ⚠ $*" >&2; }
fail()  { echo "[init-openhim] ✗ $*" >&2; EXIT_CODE=1; }

# ---- authenticate -----------------------------------------------------------
# OpenHIM uses a custom HTTPS API. For initial bootstrapping, we rely on
# basic-auth (which must be enabled in the Core config — see
# api_authenticationTypes in docker-compose.yml).
# Returns the HTTP status code of the heartbeat check.
# -----------------------------------------------------------------------------
check_api_health() {
  local status
  status=$(curl ${CURL_OPTS} -o /dev/null -w "%{http_code}" \
    --user "${EMAIL}:${PASSWORD}" \
    "${API_URL}/heartbeat" 2>/dev/null || echo "000")

  echo "$status"
}

# ---- post_config -------------------------------------------------------------
# POST a JSON payload to an OpenHIM API endpoint.
#   $1 — API endpoint path  (e.g. /channels)
#   $2 — Path to JSON file  (e.g. /config/channels.json)
#   $3 — Human-friendly label for logging
# -----------------------------------------------------------------------------
post_config() {
  local endpoint="$1"
  local json_file="$2"
  local label="$3"

  # Validate that the JSON file exists and is non-empty
  if [ ! -s "$json_file" ]; then
    fail "${label}: File not found or empty — ${json_file}"
    return
  fi

  info "Importing ${label} from ${json_file}..."

  local http_code
  http_code=$(curl ${CURL_OPTS} \
    --user "${EMAIL}:${PASSWORD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d @"${json_file}" \
    -o /dev/null \
    -w "%{http_code}" \
    "${API_URL}${endpoint}" 2>&1) || true

  case "$http_code" in
    2[0-9][0-9])
      ok "${label} imported successfully (HTTP ${http_code})."
      ;;
    401)
      fail "${label}: Authentication failed (HTTP 401). Check OPENHIM_ROOT_EMAIL and OPENHIM_ROOT_PASSWORD."
      ;;
    409)
      warn "${label}: Already exists (HTTP 409). Skipping — this is expected on re-runs."
      ;;
    *)
      fail "${label}: Unexpected response (HTTP ${http_code}). Review the OpenHIM Core logs for details."
      ;;
  esac
}

# =============================================================================
# Main
# =============================================================================
main() {
  echo "============================================================"
  echo "  OpenFMR — OpenHIM Gateway Configuration Seeder"
  echo "============================================================"
  echo ""

  # --- Step 1: Verify API health -------------------------------------------
  info "Verifying API connectivity..."
  local retry_count=0
  local max_retries=10
  local health_status

  while [ "$retry_count" -lt "$max_retries" ]; do
    health_status=$(check_api_health)

    if [ "$health_status" = "200" ]; then
      ok "OpenHIM API is healthy (HTTP 200)."
      break
    fi

    retry_count=$((retry_count + 1))
    warn "API returned HTTP ${health_status}. Retry ${retry_count}/${max_retries} in 5s..."
    sleep 5
  done

  if [ "$health_status" != "200" ]; then
    fail "Could not reach OpenHIM API after ${max_retries} retries. Aborting."
    exit 1
  fi

  # --- Step 2: Seed Clients ------------------------------------------------
  # Clients must be created BEFORE channels, because channels reference
  # client roles in their 'allow' array.
  post_config "/clients" "$CLIENTS_FILE" "Clients"

  # --- Step 3: Seed Channels -----------------------------------------------
  post_config "/channels" "$CHANNELS_FILE" "Channels"

  # --- Done ----------------------------------------------------------------
  echo ""
  if [ "$EXIT_CODE" -eq 0 ]; then
    echo "============================================================"
    ok "All configuration seeded successfully."
    echo "============================================================"
  else
    echo "============================================================"
    fail "One or more imports failed. See messages above."
    echo "============================================================"
  fi

  exit "$EXIT_CODE"
}

# Run
main "$@"
