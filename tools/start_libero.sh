#!/bin/bash
# Launch Microchip Libero SoC, starting the FlexLM license server first if needed.

FLEXLM_DIR="$HOME/FlexLM"
LICENSE_FILE="$FLEXLM_DIR/License.dat"
LOG_FILE="$FLEXLM_DIR/license.log"
PORT=1702
LIBERO_BIN="/usr/local/microchip/Libero_SoC_2026.1/Libero_SoC/Designer/bin64/libero"
TIMEOUT=30   # seconds to wait for the vendor daemons to come up

export LM_LICENSE_FILE="$PORT@localhost"
export SNPSLMD_LICENSE_FILE="$PORT@localhost"
export SALT_LICENSE_SERVER="$PORT@localhost"

server_up() {
    # True once the Libero vendor daemon reports UP
    "$FLEXLM_DIR/lmutil" lmstat -c "$PORT@localhost" -a 2>/dev/null \
        | grep -q 'actlmgrd: UP'
}

if server_up; then
    echo "License server already running."
else
    if pgrep -u "$USER" -x lmgrd >/dev/null; then
        echo "lmgrd is running but not ready yet, waiting..."
    else
        echo "Starting license server..."
        "$FLEXLM_DIR/lmgrd" -c "$LICENSE_FILE" -l "+$LOG_FILE" || {
            echo "Failed to start lmgrd." >&2
            exit 1
        }
    fi

    for ((i = 0; i < TIMEOUT; i++)); do
        server_up && break
        sleep 1
    done

    if ! server_up; then
        echo "License server did not come up within ${TIMEOUT}s. Last log lines:" >&2
        tail -n 20 "$LOG_FILE" >&2
        exit 1
    fi
    echo "License server is up."
fi

exec "$LIBERO_BIN" "$@"
