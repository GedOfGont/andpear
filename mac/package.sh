#!/bin/bash
# Builds the app and writes dist/AndPear-<version>.zip plus its sha256.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-0.1.1}"
./bundle.sh
mkdir -p dist
ZIP="dist/AndPear-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent build/AndPear.app "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
