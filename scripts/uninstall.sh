#!/usr/bin/env bash
set -euo pipefail
launchctl bootout "gui/$(id -u)/local.mytime.agent" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.mytime.agent.plist"
rm -rf "/Applications/myTime.app" "$HOME/Applications/myTime.app"
echo "myTime removed (data in ~/Library/Application Support/myTime was kept)."
