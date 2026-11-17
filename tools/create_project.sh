#!/bin/bash
# Create the Libero project from the repository sources (batch, no GUI).
#
#   tools/create_project.sh [project_dir]
#
# project_dir defaults to <repo>/polarfire_simple and must not exist yet.
# Close the Libero GUI first: there is only one license. See libero/create_project.tcl.

TOOLS_DIR="$(dirname "$(readlink -f "$0")")"
ARGS=("SCRIPT:$(readlink -f "$TOOLS_DIR/../libero/create_project.tcl")")
if [ -n "$1" ]; then
    ARGS+=("SCRIPT_ARGS:$(readlink -m "$1")")
fi
exec "$TOOLS_DIR/start_libero.sh" "${ARGS[@]}"
