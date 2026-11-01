# shellcheck shell=bash
# Summary: Show the versions of hub, git and gh.
# Usage: hub version [--build-options]
#        hub --version [--build-options]
#
# hub's own command: these are all of its options. Prints hub's version, then git's, then gh's
# first version line when gh is installed.
#
# Options:
#   --build-options   Also print git's build options (git --version --build-options).
#
#   $ hub version
#   hub 0.1.0 (brc-dd/hub)
#   git version 2.54.0
#   gh version 2.103.3 (2026-10-01)

hub_cmd_version() {
  local version
  local -a build=()
  hub::normalize_opts '' '' "$@"
  set -- "${HUB_ARGS[@]}"
  while (($#)); do
    case $1 in
      --build-options) build=(--build-options) ;;
      -h | --help) hub::usage ;;
      -?*) hub::usage_error "unknown option: $1" ;;
      *) hub::usage_error "unexpected argument: $1" ;;
    esac
    shift
  done
  version=$(<"$HUB_ROOT/VERSION") || version=unknown
  printf 'hub %s (brc-dd/hub)\n' "$version"
  git --version "${build[@]}" || return
  if command -v gh >/dev/null; then gh --version | head -n 1; fi
}
