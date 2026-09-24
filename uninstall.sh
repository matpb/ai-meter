#!/usr/bin/env bash
# AI Meter uninstaller: removes the plasmoid, the ai-meter symlink and the push timer.
# Never touches ~/.config/ai-meter/.
set -uo pipefail

ID="org.mat.aimeter"
DEST="$HOME/.local/share/plasma/plasmoids/$ID"
BIN_LINK="$HOME/.local/bin/ai-meter"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-meter"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ai-meter"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

no_plasma=0
no_systemd=0

usage() {
    cat <<'EOF'
Usage: uninstall.sh [OPTIONS]

Removes the AI Meter plasmoid, the ai-meter CLI symlink and the push timer.
Your config, accounts and cached state under ~/.config/ai-meter/ and
~/.local/state/ai-meter/ are left in place.

Options:
  --no-plasma    Skip kpackagetool6/plasmashell; just remove the copied
                 plasmoid directory.
  --no-systemd   Skip disabling/removing the systemd --user push timer.
  --help, -h     Show this help and exit.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-plasma) no_plasma=1 ;;
        --no-systemd) no_systemd=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "uninstall.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# ---- 1. remove the plasmoid -------------------------------------------------
say "Removing the plasmoid..."
if [ "$no_plasma" -eq 1 ]; then
    rm -rf "$DEST"
else
    kpackagetool6 -t Plasma/Applet -r "$ID" 2>/dev/null || rm -rf "$DEST"
    kbuildsycoca6 >/dev/null 2>&1 || true
fi

# ---- 2. remove the CLI symlink ---------------------------------------------
if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then
    say "Removing $BIN_LINK..."
    rm -f "$BIN_LINK"
fi

# ---- 3. remove the push timer ----------------------------------------------
if [ "$no_systemd" -eq 1 ]; then
    say "Skipping systemd push timer removal (--no-systemd)."
else
    say "Removing the push timer..."
    systemctl --user disable --now ai-meter-push.timer >/dev/null 2>&1 || true
    rm -f "$SYSTEMD_USER_DIR/ai-meter-push.service" "$SYSTEMD_USER_DIR/ai-meter-push.timer"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo
say "Removed. Remove the widget from your panel by right-clicking it -> Remove."
say "Restart the shell to fully unload it: setsid plasmashell --replace &>/dev/null &"
say "Your config and history are untouched at:"
say "  $CONFIG_DIR"
say "  $STATE_DIR"
say "Delete them yourself for a clean slate: rm -rf \"$CONFIG_DIR\" \"$STATE_DIR\""
