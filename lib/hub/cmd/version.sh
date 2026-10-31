# shellcheck shell=bash
# Summary: Show the versions of git, gh and hub.
# Usage: hub version
#        hub --version

hub_cmd_version() {
  git --version
  if command -v gh >/dev/null 2>&1; then gh --version | head -n 1; fi
  printf 'hub version %s (https://github.com/brc-dd/hub)\n' "$HUB_VERSION"
}
