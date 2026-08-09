#!/bin/zsh
# Install (or remove) the shoegazegazer launchd agents on macOS:
#   com.shoegazegazer.web     — keeps the web UI running at login
#   com.shoegazegazer.refresh — refreshes every profile on Friday mornings
#                               and posts a notification
#
# Usage:
#   macos/install.sh            # install / update both agents
#   macos/install.sh uninstall  # stop and remove both agents
#   PORT=8080 macos/install.sh  # use a different web port (default 4567)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
PORT="${PORT:-4567}"
LABELS=(com.shoegazegazer.web com.shoegazegazer.refresh)

if [[ "${1:-}" == "uninstall" ]]; then
  for label in "${LABELS[@]}"; do
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$AGENTS_DIR/$label.plist"
    echo "removed $label"
  done
  exit 0
fi

mkdir -p "$AGENTS_DIR"

for label in "${LABELS[@]}"; do
  plist="$AGENTS_DIR/$label.plist"
  sed -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
      -e "s|__PORT__|$PORT|g" \
      "$PROJECT_DIR/macos/$label.plist.template" > "$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "installed $label"
done

echo
echo "Web UI: http://127.0.0.1:$PORT"
echo "To get a Dock icon: open that URL in Safari, then File → Add to Dock."
