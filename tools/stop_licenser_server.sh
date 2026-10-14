#!/bin/bash
# Stop the FlexLM license server used by Microchip Libero SoC.

FLEXLM_DIR="$HOME/FlexLM"
PORT=1702

if ! pgrep -u "$USER" -x lmgrd >/dev/null; then
    echo "License server is not running."
    exit 0
fi

echo "Stopping license server..."
"$FLEXLM_DIR/lmutil" lmdown -q -force -c "$PORT@localhost" >/dev/null 2>&1

# Give lmgrd and its vendor daemons a moment to exit cleanly
for i in {1..10}; do
    pgrep -u "$USER" -x lmgrd >/dev/null || { echo "License server stopped."; exit 0; }
    sleep 1
done

echo "lmdown did not stop it, sending SIGTERM..."
pkill -u "$USER" -x lmgrd
pkill -u "$USER" -x actlmgrd
pkill -u "$USER" -x snpslmd
pkill -u "$USER" -x saltd
sleep 2

if pgrep -u "$USER" -x lmgrd >/dev/null; then
    echo "License server is still running." >&2
    exit 1
fi
echo "License server stopped."

