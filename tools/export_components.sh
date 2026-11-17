#!/bin/bash
# Export the components of the Libero project (HDL+ cores, IP cores, SmartDesign
# TOP) to libero/components/*.tcl (batch, no GUI). Run it after changing a
# component and commit the result; libero/create_project.tcl sources these files.
#
#   tools/export_components.sh [project.prjx]
#
# Close the Libero GUI first: there is only one license, and the GUI may hold
# unsaved changes. See libero/export_components.tcl.

TOOLS_DIR="$(dirname "$(readlink -f "$0")")"
PRJX="$(readlink -m "${1:-$TOOLS_DIR/../polarfire_simple/polarfire_simple.prjx}")"
exec "$TOOLS_DIR/start_libero.sh" \
    "SCRIPT:$(readlink -f "$TOOLS_DIR/../libero/export_components.tcl")" \
    "SCRIPT_ARGS:$PRJX"
