#!/bin/bash
# Builds PulseDock from source and installs it into /Applications, then opens it.
# Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS="--arch $(uname -m)" ./scripts/build-app.sh

echo "==> Installing to /Applications"
osascript -e 'quit app "PulseDock"' >/dev/null 2>&1 || true
rm -rf /Applications/PulseDock.app
cp -R dist/PulseDock.app /Applications/
xattr -dr com.apple.quarantine /Applications/PulseDock.app 2>/dev/null || true
open /Applications/PulseDock.app
echo "PulseDock is running — look for the pulse icon in the menu bar."
