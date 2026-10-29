# shellcheck shell=bash
# Summary: Show git and hub version information.
# Usage: hub version
#        hub --version

hub_cmd_version() {
  "$HUB_GIT" --version
  printf 'hub version %s\n' "$HUB_VERSION"
}
