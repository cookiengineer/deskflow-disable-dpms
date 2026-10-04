#!/bin/bash
set -euo pipefail

# Manual end-to-end test for the deskflow DPMS/screen-saver blocker.
# Stops the user service, disables DPMS/screensaver via xset, then runs
# deskflow-core with the freshly built hook.

SERVICE="deskflow-server.service"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="${HOME}/.config/Deskflow/deskflow-server.conf"

systemctl --user stop "${SERVICE}" 2>/dev/null || true

# Make sure we start from the disabled state.
xset -dpms
xset s off
xset dpms 0 0 0

echo "=== before ==="
xset q | grep -iA2 -E 'screensaver|dpms' || true

gcc -shared -fPIC -o "${HOOK_DIR}/x11hook.so" "${HOOK_DIR}/hook.c" -ldl -lX11 -lXext

# Enable logging for the test run.
X11HOOK_LOG=1 LD_PRELOAD="${HOOK_DIR}/x11hook.so" \
    /usr/bin/deskflow-core server --settings "${SETTINGS}"

# After deskflow-core exits, check that the settings were not clobbered.
echo "=== after ==="
xset q | grep -iA2 -E 'screensaver|dpms' || true

# Look ma, we fixed a shitty program!
# xset q;
