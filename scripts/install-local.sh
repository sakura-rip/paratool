#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != '--login' ) ]]; then
  print -u2 'Usage: ./scripts/install-local.sh [--login]'
  exit 1
fi
source_app="${PARATOOL_APP_SOURCE:-$PWD/dist/Paratool.app}"
if [[ ! -d "$source_app" ]]; then
  print -u2 'Build first: ./scripts/build-app.sh'
  exit 1
fi
install_dir=/Applications
if [[ ! -w "$install_dir" ]]; then
  install_dir="$HOME/Applications"
  mkdir -p "$install_dir"
fi
installed_app="$install_dir/Paratool.app"
staging_dir="$(mktemp -d "$install_dir/.paratool-install.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
ditto "$source_app" "$staging_dir/Paratool.app"
codesign --verify --strict "$staging_dir/Paratool.app"
if [[ -e "$installed_app" ]]; then
  mv "$installed_app" "$staging_dir/previous.app"
fi
if ! mv "$staging_dir/Paratool.app" "$installed_app"; then
  if [[ -e "$staging_dir/previous.app" ]]; then
    mv "$staging_dir/previous.app" "$installed_app"
  fi
  exit 1
fi
printf 'Installed: %s\n' "$installed_app"
if [[ "${1:-}" == '--login' ]]; then
  agent_file="$HOME/Library/LaunchAgents/app.paratool.login.plist"
  mkdir -p "${agent_file:h}"
  python3 - "$agent_file" "$installed_app" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'Label': 'app.paratool.login',
        'ProgramArguments': ['/usr/bin/open', '-g', sys.argv[2]],
        'RunAtLoad': True,
        'LimitLoadToSessionType': 'Aqua',
    }, f)
PY
  chmod 644 "$agent_file"
  plutil -lint "$agent_file"
  service="gui/$(id -u)/app.paratool.login"
  if launchctl print "$service" >/dev/null 2>&1; then
    launchctl bootout "$service"
  fi
  launchctl enable "$service"
  launchctl bootstrap "gui/$(id -u)" "$agent_file"
  launchctl print "$service" >/dev/null
  print 'Automatic launch at login enabled.'
fi
