#!/bin/bash
set -euo pipefail

# Build and install the deskflow DPMS/screen-saver blocker.
#
# Usage:
#   ./install.sh [systemd-user-service-name]
#
# The optional argument is the user systemd service that runs
# deskflow-core (default: deskflow-server.service). A drop-in is
# written to ~/.config/systemd/user/<service>.d/disable-dpms.conf.

SERVICE="${1:-deskflow-server.service}"
LIB_NAME="deskflow-disable-dpms.so"
LIB_PATH="/usr/local/lib/${LIB_NAME}"
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- dependencies ----------
if ! command -v gcc >/dev/null 2>&1; then
    echo "error: gcc not found (install base-devel / build-essential)" >&2
    exit 1
fi

if command -v pacman >/dev/null 2>&1; then
    echo "Detected Arch Linux (pacman)"
    if ! pacman -Qq libx11 libxext >/dev/null 2>&1; then
        echo "run: sudo pacman -S --needed libx11 libxext" >&2
        exit 1
    fi
elif command -v apt >/dev/null 2>&1; then
    echo "Detected Debian/Ubuntu (apt)"
    if ! dpkg -s libx11-dev libxext-dev >/dev/null 2>&1; then
        echo "run: sudo apt install --no-install-recommends libx11-dev libxext-dev" >&2
        exit 1
    fi
else
    echo "warning: unknown package manager, assuming X11 headers are installed"
fi

# ---------- build ----------
echo "Building ${LIB_NAME}..."
gcc -shared -fPIC -o "${HOOK_DIR}/x11hook.so" "${HOOK_DIR}/hook.c" -ldl -lX11 -lXext

# ---------- install library ----------
sudo install -Dm755 "${HOOK_DIR}/x11hook.so" "${LIB_PATH}"
echo "Installed ${LIB_PATH}"

# ---------- systemd user drop-in ----------
if command -v systemctl >/dev/null 2>&1 && [ -n "${SERVICE}" ]; then
    DROPIN_DIR="${HOME}/.config/systemd/user/${SERVICE}.d"
    DROPIN_FILE="${DROPIN_DIR}/disable-dpms.conf"

    mkdir -p "${DROPIN_DIR}"
    cat > "${DROPIN_FILE}" <<EOF
[Service]
Environment=LD_PRELOAD=${LIB_PATH}
EOF

    echo "Wrote ${DROPIN_FILE}"
    systemctl --user daemon-reload || true
    echo "Reloaded systemd user daemon"
    echo
    echo "Restart the service to apply:"
    echo "  systemctl --user restart ${SERVICE}"
fi

echo
echo "For the GUI launcher (deskflow), export the preload before starting it:"
echo "  env LD_PRELOAD=${LIB_PATH} deskflow"
echo
echo "Set X11HOOK_LOG=1 to log intercepted calls to /tmp/x11-hook.log"
