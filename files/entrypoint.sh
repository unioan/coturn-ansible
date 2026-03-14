#!/bin/sh
set -e

TEMPLATE=/etc/coturn/coturn.conf.template
CONF=/tmp/turnserver.conf

# Validate required environment variables
for var in EXTERNAL_IP RELAY_IP LISTENING_IP CERT_DIR REALM MIN_PORT MAX_PORT; do
    eval val=\$$var
    if [ -z "$val" ]; then
        echo "[entrypoint] ERROR: required variable '$var' is not set" >&2
        exit 1
    fi
done

AUTH_MODE="${AUTH_MODE:-password}"
LOG_LEVEL="${LOG_LEVEL:-normal}"

# Step 1: substitute ${VAR} placeholders using sed (envsubst not available in this image)
sed \
    -e "s|\${EXTERNAL_IP}|${EXTERNAL_IP}|g" \
    -e "s|\${RELAY_IP}|${RELAY_IP}|g" \
    -e "s|\${LISTENING_IP}|${LISTENING_IP}|g" \
    -e "s|\${CERT_DIR}|${CERT_DIR}|g" \
    -e "s|\${REALM}|${REALM}|g" \
    -e "s|\${MIN_PORT}|${MIN_PORT}|g" \
    -e "s|\${MAX_PORT}|${MAX_PORT}|g" \
    -e "s|\${CLI_PASSWORD}|${CLI_PASSWORD}|g" \
    -e "s|\${TOTAL_QUOTA}|${TOTAL_QUOTA}|g" \
    -e "s|\${USER_QUOTA}|${USER_QUOTA}|g" \
    -e "s|\${MAX_BPS}|${MAX_BPS}|g" \
    "${TEMPLATE}" > "${CONF}"

# Step 2: build auth block and substitute ##AUTH_BLOCK## sentinel via sed
# (sed instead of awk: busybox awk in Alpine has issues with multiline -v values)
case "${AUTH_MODE}" in
    password)
        if [ -z "${TURN_USER}" ] || [ -z "${TURN_PASSWORD}" ]; then
            echo "[entrypoint] ERROR: TURN_USER and TURN_PASSWORD required for password mode" >&2
            exit 1
        fi
        # Write auth block to temp file to avoid multiline quoting issues
        printf 'lt-cred-mech\nuser=%s:%s' "${TURN_USER}" "${TURN_PASSWORD}" > /tmp/auth_block.txt
        echo "[entrypoint] AUTH_MODE=password (lt-cred-mech)"
        ;;
    noauth)
        printf 'no-auth' > /tmp/auth_block.txt
        echo "[entrypoint] WARNING: AUTH_MODE=noauth — open relay, no credentials required" >&2
        ;;
    *)
        echo "[entrypoint] ERROR: Unknown AUTH_MODE='${AUTH_MODE}'. Valid values: password, noauth" >&2
        exit 1
        ;;
esac

# Replace sentinel line with auth block content
# sed: on matching line, read auth_block.txt then delete the sentinel
sed -e '/^##AUTH_BLOCK##$/{' -e 'r /tmp/auth_block.txt' -e 'd' -e '}' \
    "${CONF}" > "${CONF}.tmp" && mv "${CONF}.tmp" "${CONF}"

# Step 3: build log level block and substitute ##LOG_LEVEL_BLOCK## sentinel
case "${LOG_LEVEL}" in
    normal)
        : > /tmp/log_level_block.txt
        ;;
    verbose)
        printf 'verbose' > /tmp/log_level_block.txt
        ;;
    Verbose)
        printf 'verbose\nVerbose' > /tmp/log_level_block.txt
        ;;
    *)
        echo "[entrypoint] ERROR: Unknown LOG_LEVEL='${LOG_LEVEL}'. Valid values: normal, verbose, Verbose" >&2
        exit 1
        ;;
esac

sed -e '/^##LOG_LEVEL_BLOCK##$/{' -e 'r /tmp/log_level_block.txt' -e 'd' -e '}' \
    "${CONF}" > "${CONF}.tmp" && mv "${CONF}.tmp" "${CONF}"

# Step 4: build mobility block and substitute ##MOBILITY_BLOCK## sentinel
MOBILITY="${MOBILITY:-false}"
case "${MOBILITY}" in
    true)
        printf 'mobility' > /tmp/mobility_block.txt
        echo "[entrypoint] MOBILITY=enabled (RFC 8016)"
        ;;
    false)
        : > /tmp/mobility_block.txt
        ;;
    *)
        echo "[entrypoint] ERROR: Unknown MOBILITY='${MOBILITY}'. Valid values: true, false" >&2
        exit 1
        ;;
esac

sed -e '/^##MOBILITY_BLOCK##$/{' -e 'r /tmp/mobility_block.txt' -e 'd' -e '}' \
    "${CONF}" > "${CONF}.tmp" && mv "${CONF}.tmp" "${CONF}"

# Step 5: verify certificate files exist
CERT_FILE="${CERT_DIR}/fullchain.pem"
PKEY_FILE="${CERT_DIR}/privkey.pem"

for f in "${CERT_FILE}" "${PKEY_FILE}"; do
    if [ ! -f "$f" ]; then
        echo "[entrypoint] ERROR: certificate file not found: $f" >&2
        echo "[entrypoint]        Check CERT_DIR in .env (current value: ${CERT_DIR})" >&2
        exit 1
    fi
done

echo "[entrypoint] CERT_DIR=${CERT_DIR} | REALM=${REALM} | RELAY=${MIN_PORT}-${MAX_PORT} | EXTERNAL_IP=${EXTERNAL_IP}"

# Step 6: start turnserver as PID 1
# --log-file stdout sends output to Docker log driver (docker logs)
exec turnserver -c "${CONF}" --log-file stdout
