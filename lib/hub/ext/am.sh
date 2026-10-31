# shellcheck shell=bash
# Summary: Apply the commits behind a GitHub pull request, commit or compare URL.
# Usage: hub am [<git-am options>] (URL | MBOX)...
#
# A git command hub extends: git am's options apply, and hub recognizes one operand form before
# `--`: the URL of a GitHub pull request (.../pull/N), commit (.../commit/SHA, or
# .../pull/N/commits/SHA) or comparison (.../compare/BASE...HEAD), with or without the .patch or
# .diff suffix of its raw form. Each such URL is downloaded through gh's API as a patch series
# into a temporary file, which git am gets in its place, so the commits keep their authors and
# messages; every other argument stays as given, and the value of an option (--exclude PATH) is
# never taken for a URL. The temporary files are removed when git am ends, however it ends.
# Without any URL, this is plain git am.
#
#   $ hub am -3 https://github.com/jingweno/gh/pull/55
#   > gh api --hostname github.com repos/jingweno/gh/pulls/55 -H 'Accept: application/vnd.github.v3.patch' > $TMPDIR/hub-am.XXXXXX/1.patch
#   > git am -3 $TMPDIR/hub-am.XXXXXX/1.patch
#
#   $ hub am https://github.com/jingweno/gh/commit/fdb9921.patch
#   > gh api --hostname github.com repos/jingweno/gh/commits/fdb9921 -H 'Accept: application/vnd.github.v3.patch' > ...

hub_ext_am() { _hub_am_run am "$@"; }

# _hub_am_run am|apply ARGS... : also used by apply.sh. am downloads the patch (mbox) form of every URL;
# apply downloads the diff, or the patch when the URL's suffix asks for it.
_hub_am_run() {
  local cmd=$1 i n=0 tmp url file fmt value=0
  shift
  local -a args=("$@") urls=() gh_args
  for i in "${!args[@]}"; do
    if ((value)); then
      value=0
      continue
    fi
    case ${args[i]} in
      --) break ;;
      --help)
        hub::module_doc "$HUB_LIB/ext/$cmd.sh"
        exit 0
        ;;
      --exclude | --include | --directory | --whitespace | --build-fake-ancestor | --patch-format | --quoted-cr | --empty | --resolvemsg) value=1 ;;
      --*) ;;
      -?*) [[ ${args[i]} =~ ^-[^pC]*[pC]$ ]] && value=1 ;; # -p or -C last in a cluster takes the next argument
      *) _hub_am_url "${args[i]}" && urls+=("$i") ;;
    esac
  done
  ((${#urls[@]})) || hub::exec_git "$cmd" "$@"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hub-$cmd.XXXXXX") || exit
  # shellcheck disable=SC2064  # expand $tmp now
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in "${urls[@]}"; do
    url=${args[i]}
    _hub_am_url "$url"
    fmt='patch'
    [[ $cmd == apply ]] && fmt=${HUB_AM_FORMAT:-diff}
    file=$tmp/$((++n)).$fmt
    gh_args=(api --hostname "$HUB_URL_HOST" "$HUB_AM_ENDPOINT" -H "Accept: application/vnd.github.v3.$fmt")
    _hub_am_escapes && gh_args+=(--allow-escape-sequences)
    if ((HUB_NOOP)); then
      printf '%s > %s\n' "$(hub::quote gh "${gh_args[@]}")" "$(hub::quote "$file")"
    else
      hub::gh_query "${gh_args[@]}" >"$file" || hub::die "Aborted: could not download $url"
    fi
    args[i]=$file
  done
  hub::git "$cmd" "${args[@]}"
}

# _hub_am_url URL : true for a GitHub pull request, commit or compare URL (its raw .patch and .diff forms
# included). Sets HUB_AM_ENDPOINT (the API path that serves it) and HUB_AM_FORMAT (patch, diff or empty),
# with HUB_URL_HOST from hub::parse_github_url.
_hub_am_url() {
  HUB_AM_ENDPOINT='' HUB_AM_FORMAT=''
  hub::parse_github_url "$1" || return 1
  local path=$HUB_URL_PATH base=repos/$HUB_URL_OWNER/$HUB_URL_REPO
  HUB_AM_FORMAT=$HUB_URL_FORMAT
  case $HUB_URL_KIND in
    pull)
      if [[ -n $HUB_URL_SHA ]]; then HUB_AM_ENDPOINT=$base/commits/$HUB_URL_SHA; else HUB_AM_ENDPOINT=$base/pulls/$HUB_URL_NUMBER; fi
      ;;
    commit) HUB_AM_ENDPOINT=$base/commits/$HUB_URL_SHA ;;
    compare)
      case $path in *.patch | *.diff) HUB_AM_FORMAT=${path##*.} path=${path%.*} ;; esac
      [[ -n $path ]] || return 1
      HUB_AM_ENDPOINT=$base/compare/$path
      ;;
    *) return 1 ;;
  esac
}

# _hub_am_escapes : true if gh api has --allow-escape-sequences, without which gh 2.103 and later refuse
# to write terminal escape bytes. gh is asked once.
_hub_am_escapes() {
  [[ -n ${HUB_AM_ESCAPES+x} ]] || HUB_AM_ESCAPES=$(hub::gh_query api --help 2>/dev/null)
  [[ $HUB_AM_ESCAPES == *--allow-escape-sequences* ]]
}
