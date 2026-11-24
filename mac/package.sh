#!/bin/bash
# Builds the app and writes dist/NotifyBridge-<version>.zip plus its sha256.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-0.1.0}"
./bundle.sh
mkdir -p dist
ZIP="dist/NotifyBridge-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/NotifyBridge.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
