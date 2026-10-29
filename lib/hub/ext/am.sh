# shellcheck shell=bash
# Summary: Apply the commits behind a GitHub pull request or commit URL.
# Usage: hub am [git-am options] [URL | MBOX]...
#
# Every argument that is the URL of a GitHub pull request or commit
# (.../pull/N, .../commit/SHA, .../pull/N/commits/SHA) is downloaded with gh
# as a patch series into a temporary file, and `git am` gets that file in its
# place, so the commits keep their authors and messages. A pull request gives
# all of its commits; a commit URL gives just that commit. Other arguments go
# to git am unchanged, and without any URL this is plain `git am`.
#
#   $ hub am -3 https://github.com/jingweno/gh/pull/55
#   > gh pr diff https://github.com/jingweno/gh/pull/55 --patch --color=never > $TMPDIR/hub-am.XXXXXX/1.patch
#   > git am -3 $TMPDIR/hub-am.XXXXXX/1.patch
#
#   $ hub am https://github.com/jingweno/gh/commit/fdb9921
#   > gh api repos/jingweno/gh/commits/fdb9921 -H 'Accept: application/vnd.github.v3.patch' > ...

hub_ext_am() {
  [[ ${1-} == --help ]] && hub::usage
  _hub_am_run am patch "$@"
}

# _hub_am_run GIT-COMMAND patch|diff ARGS... : run `git GIT-COMMAND ARGS...` with each GitHub pull
# request or commit URL in ARGS replaced by a file holding its patch (or diff), downloaded with gh
# into a temporary directory that is removed on exit. Under --noop the downloads are printed too.
# Shared with apply.sh.
_hub_am_run() {
  local cmd=$1 media=$2 i n=0 tmp base
  shift 2
  local -a args=("$@") urls=()
  for i in "${!args[@]}"; do
    case ${args[i]} in
      http://* | https://*) _hub_am_parse "${args[i]}" && urls+=("$i") ;;
    esac
  done
  ((${#urls[@]})) || hub::exec_git "$cmd" "$@"

  hub::require_gh
  base=${TMPDIR:-/tmp}
  tmp=$(mktemp -d "${base%/}/hub-$cmd.XXXXXX") || hub::die "Aborted: could not create a temporary directory"
  # shellcheck disable=SC2064  # expand $tmp now: the trap fires after this function has returned
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in "${urls[@]}"; do
    n=$((n + 1))
    _hub_am_download "${args[i]}" "$media" "$tmp/$n.$media"
    args[i]=$tmp/$n.$media
  done
  hub::git "$cmd" "${args[@]}"
}

# _hub_am_parse URL : true for a GitHub pull request or commit URL; sets HUB_URL_* like hub::parse_github_url.
_hub_am_parse() {
  hub::parse_github_url "$1" || return 1
  [[ $HUB_URL_KIND == pull || ($HUB_URL_KIND == commit && -n $HUB_URL_SHA) ]]
}

# _hub_am_download URL patch|diff FILE : save the patch or diff behind URL to FILE (printed under --noop).
_hub_am_download() {
  local url=$1 media=$2 file=$3 gh_host=${GH_HOST:-github.com}
  local -a gh_args
  _hub_am_parse "$url" || hub::die "Aborted: not a pull request or commit URL: $url"
  if [[ $HUB_URL_KIND == pull && -z $HUB_URL_SHA ]]; then
    gh_args=(pr diff "$url")
    [[ $media == patch ]] && gh_args+=(--patch)
    gh_args+=(--color=never)
  else
    # One commit, also for .../pull/N/commits/SHA, where `gh pr diff` would give the whole pull request.
    gh_args=(api)
    [[ ${HUB_URL_HOST,,} == "${gh_host,,}" ]] || gh_args+=(--hostname "$HUB_URL_HOST")
    gh_args+=("repos/$HUB_URL_OWNER/$HUB_URL_REPO/commits/$HUB_URL_SHA" -H "Accept: application/vnd.github.v3.$media")
  fi
  if ((HUB_NOOP)); then
    printf '%s > %s\n' "$(hub::quote gh "${gh_args[@]}")" "$(hub::quote "$file")"
    return 0
  fi
  hub::gh_query "${gh_args[@]}" >"$file" || hub::die "Aborted: could not download $url"
}
