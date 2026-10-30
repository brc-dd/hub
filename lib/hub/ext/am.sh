# shellcheck shell=bash
# Summary: Apply the commits behind a GitHub pull request or commit URL.
# Usage: hub am [git-am options] [URL | MBOX]...
#
# Each operand that is the URL of a GitHub pull request or commit (.../pull/N,
# .../commit/SHA, .../pull/N/commits/SHA) is downloaded with gh as a patch
# series into a temporary file, which git am gets in its place, so the commits
# keep their authors and messages. Option values and the arguments after `--`
# are left alone. Without any URL, this is plain git am.
#
#   $ hub am -3 https://github.com/jingweno/gh/pull/55
#   > gh pr diff https://github.com/jingweno/gh/pull/55 --patch --color=never > $TMPDIR/hub-am.XXXXXX/1.patch
#   > git am -3 $TMPDIR/hub-am.XXXXXX/1.patch
#
#   $ hub am https://github.com/jingweno/gh/commit/fdb9921
#   > gh api --hostname github.com repos/jingweno/gh/commits/fdb9921 -H 'Accept: application/vnd.github.v3.patch' > ...

hub_ext_am() {
  [[ ${1-} == --help ]] && hub::usage
  _hub_am_run am patch "$@"
}

# _hub_am_run GIT-COMMAND patch|diff ARGS... : also used by apply.sh.
_hub_am_run() {
  local cmd=$1 media=$2 i n=0 tmp url file value=0
  shift 2
  local -a args=("$@") urls=() gh_args
  for i in "${!args[@]}"; do
    if ((value)); then
      value=0
      continue
    fi
    case ${args[i]} in
      --) break ;;
      # options whose value is the next argument; -S/--gpg-sign only take an attached one
      --exclude | --include | --directory | --whitespace | -p | -C | --build-fake-ancestor | --patch-format | --quoted-cr | --empty | --resolvemsg) value=1 ;;
      *) hub::parse_github_url "${args[i]}" && [[ $HUB_URL_KIND == pull || $HUB_URL_KIND == commit ]] && urls+=("$i") ;;
    esac
  done
  ((${#urls[@]})) || hub::exec_git "$cmd" "$@"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hub-$cmd.XXXXXX") || exit
  # shellcheck disable=SC2064  # expand $tmp now
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in "${urls[@]}"; do
    url=${args[i]} file=$tmp/$((++n)).$media
    hub::parse_github_url "$url"
    if [[ -z $HUB_URL_SHA ]]; then
      gh_args=(pr diff "$url")
      [[ $media == patch ]] && gh_args+=(--patch)
      gh_args+=(--color=never)
      _hub_am_escapes pr diff && gh_args+=(--allow-escape-sequences)
    else
      # one commit (also of a pull request), from the URL's host whatever gh's default host is
      gh_args=(api --hostname "$HUB_URL_HOST" "repos/$HUB_URL_OWNER/$HUB_URL_REPO/commits/$HUB_URL_SHA" -H "Accept: application/vnd.github.v3.$media")
      _hub_am_escapes api && gh_args+=(--allow-escape-sequences)
    fi
    if ((HUB_NOOP)); then
      printf '%s > %s\n' "$(hub::quote gh "${gh_args[@]}")" "$(hub::quote "$file")"
    else
      hub::gh_query "${gh_args[@]}" >"$file" || hub::die "Aborted: could not download $url"
    fi
    args[i]=$file
  done
  hub::git "$cmd" "${args[@]}"
}

# _hub_am_escapes GH-COMMAND... : true if it has --allow-escape-sequences, without which gh 2.103 and
# later refuse to write terminal escape bytes. gh is asked once per command.
declare -gA HUB_AM_ESCAPES=()
_hub_am_escapes() {
  [[ -v HUB_AM_ESCAPES[$*] ]] || HUB_AM_ESCAPES[$*]=$(hub::gh_query "$@" --help 2>/dev/null)
  [[ ${HUB_AM_ESCAPES[$*]} == *--allow-escape-sequences* ]]
}
