#!/usr/bin/env bash
# AI Meter installer for KDE Plasma 6: plasmoid + bundled collector, `ai-meter` CLI, optional push timer.
# Idempotent.
set -euo pipefail

ID="org.mat.aimeter"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$HERE/plasmoid/$ID"
DEST="$HOME/.local/share/plasma/plasmoids/$ID"
BIN_DIR="$HOME/.local/bin"
BIN_LINK="$BIN_DIR/ai-meter"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-meter"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

no_plasma=0
no_systemd=0

usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Installs AI Meter: the KDE Plasma panel widget, the `ai-meter` CLI (symlinked
into ~/.local/bin), and the optional push timer that feeds the phone widget.

Options:
  --no-plasma    Skip kpackagetool6/plasmashell; copy the plasmoid package
                 directly into ~/.local/share/plasma/plasmoids/ instead.
  --no-systemd   Skip installing and enabling the systemd --user push timer.
  --help, -h     Show this help and exit.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --no-plasma) no_plasma=1 ;;
        --no-systemd) no_systemd=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "install.sh: unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m  %s\n' "$*"; }

# ---- 1. dependency check ---------------------------------------------------
say "Checking dependencies..."
missing=()
for c in jq curl openssl flock timeout; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( BASH_VERSINFO[0] < 4 )); then
    missing+=("bash>=4")
fi
if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing required tools: ${missing[*]}"
    warn "Install them with your package manager, e.g.:"
    warn "  Fedora/KDE : sudo dnf install jq curl openssl util-linux coreutils"
    warn "  Arch       : sudo pacman -S jq curl openssl util-linux coreutils"
    warn "  openSUSE   : sudo zypper install jq curl openssl util-linux coreutils"
    exit 1
fi
for c in python3 sqlite3; do
    command -v "$c" >/dev/null 2>&1 || warn "Missing optional dependency: $c (only needed for the Claude browser-cookie rung)"
done

missing_plasma=()
if [ "$no_plasma" -eq 0 ]; then
    for c in kpackagetool6 plasmashell; do
        command -v "$c" >/dev/null 2>&1 || missing_plasma+=("$c")
    done
    if [ "${#missing_plasma[@]}" -gt 0 ]; then
        warn "Missing: ${missing_plasma[*]} -- re-run with --no-plasma, or install kf6-kpackage / plasma-workspace."
        exit 1
    fi
fi
if [ "$no_systemd" -eq 0 ]; then
    command -v systemctl >/dev/null 2>&1 || { warn "systemctl not found -- re-run with --no-systemd."; exit 1; }
fi

was_installed=0
[ -d "$DEST" ] && was_installed=1

# ---- 2. install the plasmoid (and collector it bundles) -------------------
if [ "$no_plasma" -eq 1 ]; then
    say "Copying the plasmoid package to $DEST (--no-plasma)..."
    rm -rf "$DEST"
    mkdir -p "$(dirname "$DEST")"
    cp -r "$PKG" "$DEST"
else
    say "Installing the plasmoid ($ID)..."
    if kpackagetool6 -t Plasma/Applet -s "$ID" >/dev/null 2>&1; then
        kpackagetool6 -t Plasma/Applet -u "$PKG"
    else
        kpackagetool6 -t Plasma/Applet -i "$PKG" 2>/dev/null || {
            warn "kpackagetool6 install failed; copying files directly."
            mkdir -p "$DEST"
            cp -rT "$PKG" "$DEST"
        }
    fi
    kbuildsycoca6 >/dev/null 2>&1 || true
fi
say "Plasmoid installed."

# ---- 3. symlink the CLI -----------------------------------------------------
say "Linking the ai-meter CLI into $BIN_DIR..."
mkdir -p "$BIN_DIR"
ln -sf "$DEST/contents/collector/ai-meter" "$BIN_LINK"
chmod +x "$DEST/contents/collector/ai-meter" 2>/dev/null || true

# ---- 4. config init ---------------------------------------------------------
say "Initializing config (auto-detecting your subscriptions if none exists)..."
"$BIN_LINK" config init >/dev/null

# ---- 5. systemd push timer --------------------------------------------------
if [ "$no_systemd" -eq 1 ]; then
    say "Skipping systemd push timer (--no-systemd)."
else
    say "Installing the push timer..."
    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$HERE/systemd/ai-meter-push.service" "$SYSTEMD_USER_DIR/"
    cp "$HERE/systemd/ai-meter-push.timer" "$SYSTEMD_USER_DIR/"
    systemctl --user daemon-reload

    if [ -f "$CONFIG_DIR/push.json" ]; then
        systemctl --user enable --now ai-meter-push.timer
        say "Push timer enabled (found $CONFIG_DIR/push.json)."
    else
        warn "No $CONFIG_DIR/push.json yet -- the push timer is installed but not enabled."
        warn "Set up phone push (see docs/phone.md), then run:"
        warn "  systemctl --user enable --now ai-meter-push.timer"
    fi
fi

# ---- 6. offer to add it to a panel -----------------------------------------
if [ "$no_plasma" -eq 0 ] && [ -t 0 ]; then
    echo
    read -r -p "Add 'AI Meter' to your top panel now? [Y/n] " a
    if [ "${a,,}" != "n" ]; then
        Q=$(command -v qdbus-qt6 || command -v qdbus6 || true)
        if [ -n "$Q" ]; then
            if "$Q" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
                var ps = panels(); var target = ps.find(p => p.location == "top") || ps[0];
                if (target) { target.addWidget("org.mat.aimeter"); }
            ' >/dev/null 2>&1; then
                say "Added to your panel."
            else
                warn "Could not add automatically -- right-click your panel -> Add Widgets -> AI Meter."
            fi
        else
            warn "qdbus not found -- right-click your panel -> Add Widgets -> AI Meter."
        fi
    fi
fi

echo
say "Done."
if [ "$no_plasma" -eq 0 ]; then
    say "If AI Meter isn't already on your panel: right-click the panel -> Add Widgets -> AI Meter."
    if [ "$was_installed" -eq 1 ]; then
        warn "Upgraded from an existing install -- if the widget looks stale, run:"
        warn "  setsid plasmashell --replace &>/dev/null &"
    fi
fi
say "Configure your subscriptions in the widget's Settings -> Meters, or edit $CONFIG_DIR/config.json directly."
