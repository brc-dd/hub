# shellcheck shell=bash
# shellcheck disable=SC2034  # HUB_* result variables are set here and read by modules
# shellcheck disable=SC2153  # HUB_ROOT is exported by bin/hub
# core.sh — shared helpers for hub modules. Sourced by bin/hub once it has
# decided to intercept a command; every module may rely on everything here.
#
# Conventions
#   - Functions are namespaced hub::<name>. A module lib/hub/{cmd,ext}/<name>.sh
#     defines hub_cmd_<name> or hub_ext_<name> (dashes become underscores) as
#     its entry point and may define private helpers prefixed _hub_<name>_.
#   - Anything with side effects goes through hub::run / hub::git / hub::gh /
#     hub::exec_git / hub::exec_gh so that `hub --noop` prints the command
#     instead of running it.
#   - Read-only lookups use hub::git_query / hub::gh_query, which always run.
#   - Errors: hub::die "Aborted: ..." (exit 1).
#   - Variables a helper "returns" by side effect are HUB_* globals and are
#     documented on the helper.

[[ -n ${HUB_CORE_LOADED:-} ]] && return 0
HUB_CORE_LOADED=1

# The version lives in the VERSION file at the project root (script/bump maintains it).
if [[ -z ${HUB_VERSION:-} ]]; then
  if [[ -r $HUB_ROOT/VERSION ]]; then read -r HUB_VERSION <"$HUB_ROOT/VERSION"; else HUB_VERSION=unknown; fi
fi
: "${HUB_NOOP:=0}"
declare -p HUB_GIT_OPTS >/dev/null 2>&1 || HUB_GIT_OPTS=()
HUB_GIT=${HUB_GIT:-}

# hub 2.x configured Enterprise hosts with GITHUB_HOST; gh reads GH_HOST. Make
# gh see the same default host, or hub would build URLs for one host while gh
# creates, deletes and queries on another.
if [[ -z ${GH_HOST:-} && -n ${GITHUB_HOST:-} ]]; then
  export GH_HOST=$GITHUB_HOST
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
hub::die() {
  printf '%s\n' "$*" >&2
  exit 1
}
hub::warn() { printf '%s\n' "$*" >&2; }
hub::debug() {
  [[ -n ${HUB_VERBOSE:-} ]] && printf 'hub: %s\n' "$*" >&2
  return 0
}

# hub::module_doc FILE : print a module's leading comment block without the '# ' prefixes.
hub::module_doc() {
  local line
  while IFS= read -r line; do
    [[ $line == '# shellcheck'* ]] && continue
    [[ $line == \#* ]] || break
    line=${line#\#}
    printf '%s\n' "${line# }"
  done <"$1"
}

# hub::usage [EXIT] : print the calling module's manual (its comment block) and exit.
hub::usage() {
  hub::module_doc "${BASH_SOURCE[1]}"
  exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Running things
# ---------------------------------------------------------------------------
# hub::quote ARGS... : one line, shell-quoted only where needed (for --noop output).
hub::quote() {
  local out='' arg
  for arg in "$@"; do
    if [[ $arg =~ ^[A-Za-z0-9_./:@%+=,^~-]+$ ]]; then
      out+="${out:+ }$arg"
    else out+="${out:+ }$(printf '%q' "$arg")"; fi
  done
  printf '%s\n' "$out"
}

# hub::run CMD ARGS... : run a command with side effects; under --noop, print it instead.
hub::run() {
  if ((HUB_NOOP)); then
    hub::quote "$@"
    return 0
  fi
  hub::debug "\$ $(hub::quote "$@")"
  "$@"
}

# hub::git ARGS... : run the real git with the forwarded global options (printed under --noop).
hub::git() {
  if ((HUB_NOOP)); then
    hub::quote git "${HUB_GIT_OPTS[@]}" "$@"
    return 0
  fi
  hub::debug "\$ $(hub::quote git "${HUB_GIT_OPTS[@]}" "$@")"
  "$HUB_GIT" "${HUB_GIT_OPTS[@]}" "$@"
}

# hub::git_query ARGS... : read-only git call; always runs, stderr silenced.
hub::git_query() { "$HUB_GIT" "${HUB_GIT_OPTS[@]}" "$@" 2>/dev/null; }

# hub::exec_git ARGS... : hand the process over to git (printed under --noop, then exit 0).
hub::exec_git() {
  if ((HUB_NOOP)); then
    hub::quote git "${HUB_GIT_OPTS[@]}" "$@"
    exit 0
  fi
  hub::debug "\$ $(hub::quote git "${HUB_GIT_OPTS[@]}" "$@")"
  exec "$HUB_GIT" "${HUB_GIT_OPTS[@]}" "$@"
}

hub::require_gh() {
  command -v gh >/dev/null 2>&1 || hub::die "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}

# hub::gh ARGS... : gh call with side effects (printed under --noop).
hub::gh() {
  hub::require_gh
  hub::run gh "$@"
}

# hub::gh_query ARGS... : read-only gh call that always runs (used to work out what to do).
hub::gh_query() {
  hub::require_gh
  hub::debug "\$ $(hub::quote gh "$@")"
  gh "$@"
}

# hub::exec_gh ARGS... : hand the process over to gh (printed under --noop, then exit 0).
hub::exec_gh() {
  hub::require_gh
  if ((HUB_NOOP)); then
    hub::quote gh "$@"
    exit 0
  fi
  hub::debug "\$ $(hub::quote gh "$@")"
  exec gh "$@"
}

# hub::realpath PATH : absolute path with symlinks resolved.
hub::realpath() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
    return
  fi
  local p=$1 link
  while [[ -L $p ]]; do
    link=$(readlink "$p")
    [[ $link == /* ]] || link=$(dirname "$p")/$link
    p=$link
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd -P)" "$(basename "$p")"
}

# hub::find_git : locate the real git binary (never ourselves, even if someone installed hub as "git").
hub::find_git() {
  [[ -n $HUB_GIT ]] && return 0
  local dir candidate self
  self=$(hub::realpath "$HUB_ROOT/bin/hub" 2>/dev/null || true)
  local IFS=:
  for dir in $PATH; do
    candidate=${dir:-.}/git
    [[ -x $candidate && ! -d $candidate ]] || continue
    [[ -n $self && $(hub::realpath "$candidate") == "$self" ]] && continue
    HUB_GIT=$candidate
    return 0
  done
  hub::die "hub: git not found in PATH"
}

# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------
hub::in_repo() { [[ $(hub::git_query rev-parse --is-inside-work-tree) == true ]]; }
hub::require_repo() { hub::in_repo || hub::die "fatal: not a git repository (or any of the parent directories): .git"; }
hub::current_branch() { hub::git_query symbolic-ref -q --short HEAD; }
hub::git_dir() { hub::git_query rev-parse --git-dir; }

# ---------------------------------------------------------------------------
# Hosts and URLs
# ---------------------------------------------------------------------------
# hub::host : the default GitHub host, following gh's rule: GH_HOST (or hub 2.x's GITHUB_HOST),
# else the only host gh is logged in to, else github.com. Cached per process in HUB_DEFAULT_HOST.
hub::host() {
  if [[ -n ${GH_HOST:-${GITHUB_HOST:-}} ]]; then
    printf '%s\n' "${GH_HOST:-$GITHUB_HOST}"
    return 0
  fi
  if [[ -z ${HUB_DEFAULT_HOST:-} ]]; then
    HUB_DEFAULT_HOST=github.com
    local file=${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml line host='' count=0
    if [[ -r $file ]]; then
      while IFS= read -r line; do
        [[ $line =~ ^([A-Za-z0-9.-]+):[[:space:]]*$ ]] || continue
        host=${BASH_REMATCH[1]}
        ((count++))
      done <"$file"
      ((count == 1)) && HUB_DEFAULT_HOST=$host
    fi
  fi
  printf '%s\n' "$HUB_DEFAULT_HOST"
}

# hub::known_hosts : github.com plus GH_HOST/GITHUB_HOST and `git config hub.host` entries.
hub::known_hosts() {
  {
    printf 'github.com\n'
    [[ -n ${GH_HOST:-} ]] && printf '%s\n' "$GH_HOST"
    [[ -n ${GITHUB_HOST:-} ]] && printf '%s\n' "$GITHUB_HOST"
    hub::git_query config --get-all hub.host
  } | awk 'NF && !seen[tolower($0)]++'
}

hub::is_known_host() {
  local h want=${1,,}
  while IFS= read -r h; do [[ ${h,,} == "$want" ]] && return 0; done < <(hub::known_hosts)
  return 1
}

# hub::ssh_hostname ALIAS : resolve an ssh_config alias to its HostName with `ssh -G` (empty if none).
hub::ssh_hostname() {
  command -v ssh >/dev/null 2>&1 || return 1
  ssh -G "$1" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }'
}

# hub::parse_remote_url URL : sets HUB_URL_HOST, HUB_URL_OWNER, HUB_URL_REPO from a git remote URL.
# Accepts https://, ssh://, git://, git+ssh:// and scp-like git@host:owner/repo[.git]. Returns 1 otherwise.
hub::parse_remote_url() {
  local url=$1 rest
  HUB_URL_HOST='' HUB_URL_OWNER='' HUB_URL_REPO=''
  case $url in
    *://*)
      rest=${url#*://}
      rest=${rest#*@}
      HUB_URL_HOST=${rest%%/*}
      HUB_URL_HOST=${HUB_URL_HOST%%:*}
      rest=${rest#*/}
      ;;
    /* | ./* | ../*) return 1 ;;
    *:*)
      rest=${url#*@}
      HUB_URL_HOST=${rest%%:*}
      rest=${rest#*:}
      ;;
    *) return 1 ;;
  esac
  rest=${rest#/}
  [[ $rest == */* ]] || return 1
  HUB_URL_OWNER=${rest%%/*}
  rest=${rest#*/}
  HUB_URL_REPO=${rest%%/*}
  HUB_URL_REPO=${HUB_URL_REPO%.git}
  [[ $HUB_URL_HOST == ssh.github.com ]] && HUB_URL_HOST=github.com
  [[ -n $HUB_URL_HOST && -n $HUB_URL_OWNER && -n $HUB_URL_REPO ]]
}

# hub::remote_project NAME : print owner/repo for a GitHub remote and set HUB_PROJECT_HOST. Returns 1 if not GitHub.
hub::remote_project() {
  local url real
  url=$(hub::git_query remote get-url "$1") || return 1
  hub::parse_remote_url "$url" || return 1
  if ! hub::is_known_host "$HUB_URL_HOST"; then
    real=$(hub::ssh_hostname "$HUB_URL_HOST")
    [[ -n $real ]] && hub::is_known_host "$real" || return 1
    HUB_URL_HOST=$real
  fi
  HUB_PROJECT_HOST=$HUB_URL_HOST
  printf '%s/%s\n' "$HUB_URL_OWNER" "$HUB_URL_REPO"
}

# hub::main_remote : the remote hub treats as "the" GitHub project: upstream, github, origin, then any other GitHub remote.
hub::main_remote() {
  local -a names
  mapfile -t names < <(hub::git_query remote)
  local r pref
  for pref in upstream github origin; do
    for r in "${names[@]}"; do
      [[ $r == "$pref" ]] && hub::remote_project "$r" >/dev/null && {
        printf '%s\n' "$r"
        return 0
      }
    done
  done
  for r in "${names[@]}"; do
    hub::remote_project "$r" >/dev/null && {
      printf '%s\n' "$r"
      return 0
    }
  done
  return 1
}

# hub::main_project : owner/repo of the current project (GH_REPO=[HOST/]OWNER/REPO overrides); sets HUB_PROJECT_HOST. Dies if none.
hub::main_project() {
  if [[ -n ${GH_REPO:-} ]]; then
    local p=${GH_REPO#*://}
    case $p in
      */*/*)
        HUB_PROJECT_HOST=${p%%/*}
        p=${p#*/}
        ;;
      *) HUB_PROJECT_HOST=$(hub::host) ;;
    esac
    printf '%s\n' "${p%.git}"
    return 0
  fi
  local remote
  remote=$(hub::main_remote) || hub::die "Aborted: could not find a GitHub remote in this repository (looked for upstream, github, origin)"
  hub::remote_project "$remote"
}

# hub::default_branch [REMOTE] : from refs/remotes/REMOTE/HEAD, else from gh, else "main".
hub::default_branch() {
  local remote=${1:-} ref proj
  [[ -n $remote ]] || remote=$(hub::main_remote) || {
    printf 'main\n'
    return 0
  }
  if ref=$(hub::git_query symbolic-ref -q --short "refs/remotes/$remote/HEAD"); then
    printf '%s\n' "${ref#"$remote"/}"
    return 0
  fi
  if hub::remote_project "$remote" >/dev/null; then
    proj=$HUB_PROJECT_HOST/$HUB_URL_OWNER/$HUB_URL_REPO # always with the host: gh's default host may differ
    if ref=$(hub::gh_query repo view "$proj" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) && [[ -n $ref ]]; then
      printf '%s\n' "$ref"
      return 0
    fi
  fi
  printf 'main\n'
}

# hub::parse_github_url URL : sets HUB_URL_HOST, HUB_URL_OWNER, HUB_URL_REPO, HUB_URL_KIND, HUB_URL_NUMBER, HUB_URL_SHA, HUB_URL_PATH
# for a GitHub web URL. KIND is repo | pull | issues | commit | gist | <first path segment, e.g. tree, blob, compare>.
# For pull URLs, HUB_URL_SHA is set when the URL points at one commit of the PR (.../pull/N/commits/SHA).
hub::parse_github_url() {
  local url=$1 host a b rest kind tail
  HUB_URL_HOST='' HUB_URL_OWNER='' HUB_URL_REPO='' HUB_URL_KIND='' HUB_URL_NUMBER='' HUB_URL_SHA='' HUB_URL_PATH=''
  [[ $url =~ ^https?://([^/?#]+)/([^/?#]+)(/([^/?#]+)(/([^?#]*))?)?/?([?#].*)?$ ]] || return 1
  host=${BASH_REMATCH[1]} a=${BASH_REMATCH[2]} b=${BASH_REMATCH[4]} rest=${BASH_REMATCH[6]}
  if [[ $host == gist.* ]]; then
    HUB_URL_HOST=${host#gist.} HUB_URL_KIND=gist
    if [[ -n $b ]]; then HUB_URL_OWNER=$a HUB_URL_NUMBER=$b; else HUB_URL_NUMBER=$a; fi
    return 0
  fi
  hub::is_known_host "$host" || return 1
  [[ -n $b ]] || return 1
  HUB_URL_HOST=$host HUB_URL_OWNER=$a HUB_URL_REPO=${b%.git}
  rest=${rest%/}
  if [[ -z $rest ]]; then
    HUB_URL_KIND=repo
    return 0
  fi
  kind=${rest%%/*}
  tail=${rest#"$kind"}
  tail=${tail#/}
  HUB_URL_KIND=$kind
  case $kind in
    pull | issues)
      HUB_URL_NUMBER=${tail%%/*}
      [[ $HUB_URL_NUMBER =~ ^[0-9]+$ ]] || return 1
      if [[ $tail == */commits/* ]]; then
        HUB_URL_SHA=${tail##*/commits/}
        HUB_URL_SHA=${HUB_URL_SHA%%/*}
      fi
      ;;
    commit) HUB_URL_SHA=${tail%%/*} ;;
    *) HUB_URL_PATH=$tail ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Identity, protocol, project shorthand
# ---------------------------------------------------------------------------
# hub::current_user [HOST] : your login on HOST. Uses gh's cached login unless a token in the
# environment overrides gh's stored credentials (then only the API knows whose token it is). Dies if unknown.
hub::current_user() {
  local host=${1:-$(hub::host)} user
  if [[ -z ${GH_TOKEN:-}${GITHUB_TOKEN:-}${GH_ENTERPRISE_TOKEN:-}${GITHUB_ENTERPRISE_TOKEN:-} ]]; then
    user=$(hub::gh_query config get user -h "$host" 2>/dev/null) && [[ -n $user ]] && {
      printf '%s\n' "$user"
      return 0
    }
  fi
  user=$(hub::gh_query api --hostname "$host" user -q .login 2>/dev/null) && [[ -n $user ]] && {
    printf '%s\n' "$user"
    return 0
  }
  hub::die "Aborted: could not determine your GitHub login for $host; run 'gh auth login'"
}

# hub::protocol [HOST] : "https" or "ssh" — HUB_PROTOCOL, else git config hub.protocol, else gh's git_protocol for HOST, else https.
hub::protocol() {
  local host=${1:-} p
  [[ -n $host ]] || host=$(hub::host)
  p=${HUB_PROTOCOL:-}
  [[ -n $p ]] || p=$(hub::git_query config --get hub.protocol) || p=''
  [[ -n $p ]] || p=$(hub::gh_query config get git_protocol -h "$host" 2>/dev/null) || p=''
  case $p in
    ssh | git) printf 'ssh\n' ;;
    *) printf 'https\n' ;;
  esac
}

# hub::git_url OWNER/REPO [HOST] [PROTOCOL] : clone URL for a project. On *.ghe.com hosts the SSH user is the tenant, as in gh.
hub::git_url() {
  local proj=$1 host=${2:-} proto=${3:-} user=git
  [[ -n $host ]] || host=$(hub::host)
  [[ -n $proto ]] || proto=$(hub::protocol "$host")
  case $proto in
    ssh | git)
      [[ ${host,,} == *.ghe.com ]] && user=${host%%.*}
      printf '%s@%s:%s.git\n' "$user" "$host" "$proj"
      ;;
    *) printf 'https://%s/%s.git\n' "$host" "$proj" ;;
  esac
}

# hub::is_shorthand STR : "owner/repo" or "repo" (dots allowed in the repo part) that is not an existing path.
hub::is_shorthand() {
  [[ $1 =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$ || $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || return 1
  [[ -e $1 ]] && return 1
  return 0
}

# hub::expand_project STR : "repo" -> "<your login>/repo"; "owner/repo" unchanged.
hub::expand_project() {
  local user
  case $1 in
    */*) printf '%s\n' "$1" ;;
    *)
      user=$(hub::current_user) || return 1
      printf '%s/%s\n' "$user" "$1"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Text, browser, clipboard, prompts
# ---------------------------------------------------------------------------
# hub::split_message TEXT : sets HUB_MSG_TITLE (first paragraph, lines joined by spaces) and HUB_MSG_BODY (the rest, trimmed).
hub::split_message() {
  local text=$1 line in_title=1 title='' body=''
  while IFS= read -r line || [[ -n $line ]]; do
    if ((in_title)); then
      if [[ -z ${line//[[:space:]]/} ]]; then
        ((${#title})) && in_title=0
        continue
      fi
      title+="${title:+ }${line}"
    else
      body+="${line}"$'\n'
    fi
  done <<<"$text"
  body=${body#"${body%%[![:space:]]*}"}
  body=${body%"${body##*[![:space:]]}"}
  HUB_MSG_TITLE=$title
  HUB_MSG_BODY=$body
}

# hub::open_url URL : open in the browser (GH_BROWSER, BROWSER, else open/xdg-open). Printed under --noop.
hub::open_url() {
  local url=$1
  if ((HUB_NOOP)); then
    hub::quote open "$url"
    return 0
  fi
  if [[ -n ${GH_BROWSER:-} ]]; then
    eval "$GH_BROWSER \"\$url\""
  elif [[ -n ${BROWSER:-} ]]; then
    eval "$BROWSER \"\$url\""
  elif command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  else
    hub::die "Aborted: no browser found; set BROWSER or print the URL instead"
  fi
}

# hub::copy TEXT : put TEXT on the clipboard (pbcopy, wl-copy or xclip). Printed under --noop.
hub::copy() {
  if ((HUB_NOOP)); then
    printf 'copy to clipboard: %s\n' "$1"
    return 0
  fi
  local tool
  for tool in pbcopy wl-copy "xclip -selection clipboard"; do
    command -v "${tool%% *}" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2086
    printf '%s' "$1" | $tool
    return
  done
  hub::die "Aborted: no clipboard tool found (pbcopy, wl-copy or xclip)"
}

# hub::confirm PROMPT : ask y/N on the terminal; true if confirmed. Not interactive -> false.
hub::confirm() {
  [[ -t 0 ]] || return 1
  local answer
  read -r -p "$1 " answer
  [[ $answer =~ ^[Yy]([Ee][Ss])?$ ]]
}
