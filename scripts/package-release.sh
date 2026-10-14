#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build-app.sh
arch="$(uname -m)"
if [[ -n "${EXPECTED_ARCH:-}" && "$arch" != "$EXPECTED_ARCH" ]]; then
  print -u2 "Wrong runner architecture: expected $EXPECTED_ARCH, got $arch"
  exit 1
fi
lipo dist/Paratool.app/Contents/MacOS/Paratool -verify_arch "$arch"
version="${APP_VERSION:-0.1.0}"
archive="$PWD/dist/Paratool-${version}-macos-${arch}.zip"
# ditto preserves the executable bit, bundle structure, and macOS metadata.
ditto -c -k --sequesterRsrc --keepParent dist/Paratool.app "$archive"
unzip -t "$archive" >/dev/null
printf 'Release archive: %s\n' "$archive"
