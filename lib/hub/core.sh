# shellcheck shell=bash
# Summary: Shared helpers of hub's modules.
#
# Sourced by bin/hub with HUB_ROOT, HUB_LIB and HUB_COMMAND set. A helper prints its answer on
# stdout and returns non-zero when it has none, unless its contract says it sets a HUB_* global.

HUB_ARGS=() HUB_OPERANDS=() HUB_OPTIONS=() HUB_FLAGS='' HUB_REST=''
declare -gA HUB_URL=()
# gh reads GH_HOST; hub 2.x users have GITHUB_HOST.
if [[ -z ${GH_HOST-} && -n ${GITHUB_HOST-} ]]; then export GH_HOST=$GITHUB_HOST; fi

# _hub_core_say MSG : print "hub COMMAND: MSG" on stderr.
_hub_core_say() { printf 'hub%s: %s\n' "${HUB_COMMAND:+ $HUB_COMMAND}" "$1" >&2; }

# hub::die MSG... : print "hub COMMAND: MSG" on stderr and exit 1.
hub::die() {
  _hub_core_say "$*"
  exit 1
}

# hub::usage_error MSG : the error line, then the module's Usage lines, on stderr; exit 1.
hub::usage_error() {
  _hub_core_say "$1"
  hub::module_doc "$HUB_LIB/cmd/$HUB_COMMAND.sh" | sed -n '/^Usage:/,/^$/{/./p;}' >&2
  exit 1
}

# hub::warn MSG... : print "hub COMMAND: warning: MSG" on stderr.
hub::warn() { _hub_core_say "warning: $*"; }

# hub::usage : print the module's manual and exit 0.
hub::usage() {
  hub::module_doc "$HUB_LIB/cmd/$HUB_COMMAND.sh"
  exit 0
}

# hub::module_doc FILE : the leading # lines of FILE without "# ", shellcheck lines skipped.
hub::module_doc() { sed -n '/^#/!q; /^# shellcheck /d; s/^#//; s/^ //; p' "$1"; }

# hub::quote ARGS... : the words on one line, each quoted with printf %q.
hub::quote() {
  local line
  printf -v line '%q ' "$@"
  printf '%s\n' "${line% }"
}

# hub::shown WORD : WORD for a message; empty, whitespace and control characters get hub::quote.
hub::shown() {
  if [[ -n $1 && $1 != *[[:space:][:cntrl:]]* ]]; then
    printf '%s\n' "$1"
  else
    hub::quote "$1"
  fi
}

# hub::run CMD ARGS... : run a command with side effects; under --noop print it instead.
hub::run() {
  if [[ ${HUB_NOOP-} == 1 ]]; then hub::quote "$@"; else "$@"; fi
}

# hub::git ARGS... : git with side effects.
hub::git() { hub::run git "$@"; }

# hub::gh ARGS... : gh with side effects.
hub::gh() { hub::require_gh && hub::run gh "$@"; }

# hub::exec_git ARGS... : hand the process over to git; under --noop print the line and exit 0.
hub::exec_git() {
  [[ ${HUB_NOOP-} != 1 ]] || { hub::quote git "$@" && exit 0; }
  exec git "$@"
}

# hub::exec_gh ARGS... : hand the process over to gh; under --noop print the line and exit 0.
hub::exec_gh() {
  hub::require_gh
  [[ ${HUB_NOOP-} != 1 ]] || { hub::quote gh "$@" && exit 0; }
  exec gh "$@"
}

# hub::git_query ARGS... : read-only git, stderr silenced; runs under --noop too.
hub::git_query() { git "$@" 2>/dev/null; }

# hub::gh_query ARGS... : read-only gh, stderr silenced; runs under --noop too.
hub::gh_query() { hub::require_gh && gh "$@" 2>/dev/null; }

# hub::require_gh : die unless gh is on PATH.
hub::require_gh() {
  command -v gh >/dev/null \
    || hub::die 'this command needs the GitHub CLI, gh (https://cli.github.com)'
}

# hub::require_repo : die unless inside a work tree, with git's own message when it has one.
hub::require_repo() {
  local out
  # A malformed configuration value or unsafe ownership: git's lines say what is wrong.
  if ! out=$(git rev-parse --is-inside-work-tree 2>&1); then
    printf '%s\n' "$out" >&2
    exit 1
  fi
  [[ $out == true ]] || hub::die 'not inside a work tree'
}

# hub::toplevel : the top directory of the work tree.
hub::toplevel() { git rev-parse --show-toplevel 2>/dev/null; }

# hub::current_branch : the branch HEAD is on; fails when detached.
hub::current_branch() {
  local ref
  # Not --short: next to a tag of the same name it prints heads/NAME.
  ref=$(git symbolic-ref --quiet HEAD 2>/dev/null) || return 1
  [[ $ref == refs/heads/?* ]] && printf '%s\n' "${ref#refs/heads/}"
}

# hub::remotes : the remote names, one per line.
hub::remotes() { git remote 2>/dev/null; }

# hub::remote_exists NAME : NAME is a remote.
hub::remote_exists() {
  local name
  # git remote lists the remotes of every configuration file and -c; get-url finds .git/remotes.
  while IFS= read -r name; do [[ $name != "$1" ]] || return 0; done < <(hub::remotes)
  git remote get-url -- "$1" >/dev/null 2>&1
}

# hub::valid_remote_name NAME : NAME can name a remote.
hub::valid_remote_name() { [[ $1 != -* ]] && git check-ref-format "refs/remotes/$1/HEAD"; }

# hub::remote_head REMOTE : the branch refs/remotes/REMOTE/HEAD points at, when both refs exist.
hub::remote_head() {
  local ref head=refs/remotes/$1/
  ref=$(git symbolic-ref --quiet "${head}HEAD" 2>/dev/null) && [[ $ref == "$head"?* ]] \
    && git show-ref --verify --quiet "$ref" && printf '%s\n' "${ref#"$head"}"
}

# hub::require_new_remote NAME : die unless NAME can name a remote and no remote has it.
hub::require_new_remote() {
  hub::valid_remote_name "$1" || hub::die "not a remote name: $(hub::shown "$1")"
  ! hub::remote_exists "$1" \
    || hub::die "remote already exists: $1 (name another with --remote-name NAME)"
}

# hub::default_branch HOST OWNER REPO [REMOTE] : REMOTE's remote_head, else gh's; never dies.
hub::default_branch() {
  local ref
  if [[ -n ${4-} ]] && hub::remote_head "$4"; then return 0; fi
  [[ -n $1 ]] || return 1
  # Without gh, bash's "command not found" goes to /dev/null too, and the answer is empty.
  ref=$(gh repo view "$1/$2/$3" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
  [[ -n $ref ]] && printf '%s\n' "$ref"
}

# hub::repo_name : the project's repository name, else the name of the repository's directory.
hub::repo_name() {
  local project dir
  # An invalid GH_REPO is an error, not a reason to take the directory's name.
  if [[ -n ${GH_REPO-} ]]; then
    project=$(hub::project) || return 1
  else
    project=$(hub::project 2>/dev/null)
  fi
  [[ -n $project ]] && printf '%s\n' "${project##* }" && return 0
  dir=$(hub::toplevel) || dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  dir=${dir%/.git} && dir=${dir##*/} && dir=${dir%.git}
  printf '%s\n' "${dir//[^A-Za-z0-9_.-]/-}"
}

# hub::push_remote BRANCH : the remote hub pushes BRANCH to and reads it back from.
hub::push_remote() {
  local branch=$1 remote ref host owner repo
  local -a remotes mine=()
  local -A logins=()
  if remote=$(git config "branch.$1.pushRemote") || remote=$(git config remote.pushDefault); then
    # git refuses to push to an empty name; hub does not look further either.
    [[ -n $remote ]] || return 1
    printf '%s\n' "$remote"
    return 0
  fi
  read -r remote ref < <(git for-each-ref \
    --format='%(upstream:remotename) %(upstream:remoteref)' "refs/heads/$branch")
  # An upstream of another name is a start point (checkout -b fix origin/main), not a destination.
  [[ -n $remote && $remote != . && $ref == "refs/heads/$branch" ]] \
    && printf '%s\n' "$remote" && return 0
  mapfile -t remotes < <(hub::remotes)
  ((${#remotes[@]} == 1)) && printf '%s\n' "${remotes[0]}" && return 0
  for remote in "${remotes[@]}"; do
    read -r host owner repo < <(hub::remote_project "$remote" push) || continue
    # Without your login hub cannot tell your fork from the parent: no guess.
    [[ -n ${logins[$host]-} ]] || logins[$host]=$(hub::login "$host" 2>/dev/null) || return 1
    [[ ${owner,,} != "${logins[$host],,}" ]] || mine+=("$remote")
  done
  if ((${#mine[@]} == 1)); then
    printf '%s\n' "${mine[0]}"
  elif hub::remote_exists origin; then
    printf '%s\n' origin
  else
    return 1
  fi
}

# hub::pushed BRANCH REMOTE : 0 pushed; 1 no BRANCH or REMOTE/BRANCH; 2 and the unpushed count.
hub::pushed() {
  local ref=refs/remotes/$2/$1
  git rev-parse --verify --quiet "refs/heads/$1" >/dev/null || return 1
  git rev-parse --verify --quiet "$ref" >/dev/null || return 1
  git merge-base --is-ancestor "refs/heads/$1" "$ref" && return 0
  git rev-list --count "$ref..refs/heads/$1"
  return 2
}

# hub::gh_hosts : the hosts gh is logged in to, one per line.
hub::gh_hosts() {
  local file=${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml line key
  [[ -f $file ]] || return 0
  while IFS= read -r line; do
    [[ $line =~ ^([^[:space:]#][^:]*):[[:space:]]*(#.*)?$ ]] || continue
    key=${BASH_REMATCH[1]}
    [[ $key != \"*\" && $key != \'*\' ]] || key=${key:1:${#key}-2}
    printf '%s\n' "$key"
  done <"$file"
}

# hub::host : the default host: GH_HOST, else the one host gh is logged in to, else github.com.
hub::host() {
  local host=${GH_HOST-}
  local -a hosts
  if [[ -z $host ]]; then
    mapfile -t hosts < <(hub::gh_hosts)
    host=github.com
    ((${#hosts[@]} != 1)) || host=${hosts[0]}
  fi
  # The host goes to git and gh inside URLs and HOST/OWNER/REPO words: no option, no path.
  [[ ${host,,} =~ ^[a-z0-9][a-z0-9.-]*$ ]] || hub::die "not a host name: $(hub::shown "$host")"
  printf '%s\n' "${host,,}"
}

# hub::known_host HOST : HOST is github.com, GH_HOST or a gh host, ignoring case.
hub::known_host() {
  local host
  local -a hosts
  mapfile -t hosts < <(hub::gh_hosts)
  for host in github.com "${GH_HOST-}" "${hosts[@]}"; do
    [[ -z $host || ${host,,} != "${1,,}" ]] || return 0
  done
  return 1
}

# hub::parse_url URL : "HOST OWNER REPO" of a GitHub remote URL.
hub::parse_url() {
  local url=$1 host raw path owner repo ssh=0
  case $url in
    https://* | http://* | git://*) url=${url#*://} ;;
    ssh://* | git+ssh://* | ssh+git://*) url=${url#*://} ssh=1 ;;
    *://*) return 1 ;;
    # scp-like only with no / before the first colon: git reads anything else as a path.
    *:*) if [[ ${url%%:*} != */* ]]; then url=${url/:/\/} ssh=1; else return 1; fi ;;
    *) return 1 ;;
  esac
  host=${url%%/*} path=${url#*/}
  raw=${host##*@} && raw=${raw%%:*} && host=${raw,,}
  path=${path%/} && path=${path%.git}
  # The host may go to ssh -G: it must not read as an option.
  [[ $host =~ ^[a-z0-9_][a-z0-9_.-]*$ && $path == */* ]] && hub::is_shorthand "$path" || return 1
  owner=${path%%/*} repo=${path#*/}
  if ((ssh)) && ! hub::known_host "$host"; then
    # ssh matches Host patterns case-sensitively: the alias goes as written.
    host=$(ssh -G "$raw" 2>/dev/null | awk '$1 == "hostname" { print tolower($2); exit }')
  fi
  ((ssh == 0)) || [[ $host != ssh.github.com ]] || host=github.com
  hub::known_host "$host" && printf '%s %s %s\n' "$host" "$owner" "$repo"
}

# hub::remote_project REMOTE [push] : "HOST OWNER REPO" of REMOTE's fetch (or push) URL.
hub::remote_project() {
  local url
  url=$(git remote get-url ${2:+"--push"} -- "$1" 2>/dev/null) && hub::parse_url "$url"
}

# _hub_core_find_remote [PROJECT] : "REMOTE HOST OWNER REPO" of the first GitHub remote (PROJECT's).
_hub_core_find_remote() {
  local remote found
  local -a remotes
  mapfile -t remotes < <(hub::remotes)
  for remote in upstream github origin "${remotes[@]}"; do
    found=$(hub::remote_project "$remote") || continue
    [[ -z ${1-} || ${found,,} == "${1,,}" ]] && printf '%s %s\n' "$remote" "$found" && return 0
  done
  return 1
}

# hub::project : "HOST OWNER REPO" of the current project: GH_REPO, else the first GitHub remote.
hub::project() {
  local found
  if [[ -n ${GH_REPO-} ]]; then
    # A bad GH_HOST is its own message, not a bad GH_REPO.
    hub::host >/dev/null || exit 1
    hub::parse_project "$GH_REPO" && return 0
    hub::die 'GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL'
  fi
  found=$(_hub_core_find_remote) \
    || hub::die 'no GitHub remote found (looked for upstream, github, origin)'
  printf '%s\n' "${found#* }"
}

# hub::project_remote : the first remote whose repository is the project.
hub::project_remote() {
  local found
  found=$(hub::project 2>/dev/null) && found=$(_hub_core_find_remote "$found") || return 1
  printf '%s\n' "${found%% *}"
}

# hub::parse_project WORD : "HOST OWNER REPO" of [HOST/]OWNER/REPO[.git] or a URL, parts checked.
hub::parse_project() {
  local host owner repo
  if [[ $1 == *:* ]]; then
    hub::parse_url "$1"
    return
  fi
  if [[ $1 =~ ^([^/]+)/([^/]+)/([^/]+)$ ]]; then
    host=${BASH_REMATCH[1],,} owner=${BASH_REMATCH[2]} repo=${BASH_REMATCH[3]}
    # cli/cli/issues is a typo, not a host. The host goes to gh: no option, no path.
    [[ $host == *.* ]] || hub::known_host "$host" || return 1
    [[ $host =~ ^[a-z0-9][a-z0-9.-]*$ ]] || return 1
  elif [[ $1 =~ ^([^/]+)/([^/]+)$ ]]; then
    owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]}
    host=$(hub::host) || return 1
  else
    return 1
  fi
  repo=${repo%.git}
  hub::is_shorthand "$owner/$repo" && printf '%s %s %s\n' "$host" "$owner" "$repo"
}

# hub::parse_github_url URL : sets HUB_URL to the host owner repo kind number sha format range.
hub::parse_github_url() {
  local host path
  local -a part
  HUB_URL=()
  # read keeps only a word's first line: a word with a newline is not one URL.
  [[ $1 != *[[:space:][:cntrl:]]* && $1 =~ ^https?://([^/?#]+)/([^?#]*) ]] || return 1
  host=${BASH_REMATCH[1],,} path=${BASH_REMATCH[2]%/}
  host=${host%%:*}
  hub::known_host "$host" || return 1
  IFS=/ read -r -a part <<<"$path"
  [[ -n ${part[0]-} && -n ${part[1]-} ]] || return 1
  HUB_URL=([host]=$host [owner]=${part[0]} [repo]=${part[1]%.git} [kind]=${part[2]:-repo})
  if ((${#part[@]} > 2)) && [[ $path =~ \.(patch|diff)$ ]]; then
    HUB_URL[format]=${BASH_REMATCH[1]} path=${path%.*}
    IFS=/ read -r -a part <<<"$path"
  fi
  case ${HUB_URL[kind]} in
    pull | issues) [[ ! ${part[3]-} =~ ^[0-9]+$ ]] || HUB_URL[number]=${part[3]} ;;&
    pull) [[ ${part[4]-} != commits || -z ${part[5]-} ]] || HUB_URL[sha]=${part[5]} ;;
    commit) HUB_URL[sha]=${part[3]-} ;;
    compare) [[ -z ${part[3]-} ]] || HUB_URL[range]=${path#*/*/compare/} ;;
  esac
  [[ -z ${HUB_URL[sha]+set} || ${HUB_URL[sha]} =~ ^[0-9a-fA-F]{4,64}$ ]]
}

# hub::login [HOST] : your login on HOST (default: hub::host); dies without gh or without one.
hub::login() {
  local host=${1:-$(hub::host)} login=
  hub::require_gh
  # A token variable overrides gh's stored account, whose cached user may be someone else.
  if [[ -z ${GH_TOKEN-}${GITHUB_TOKEN-}${GH_ENTERPRISE_TOKEN-}${GITHUB_ENTERPRISE_TOKEN-} ]]; then
    login=$(hub::gh_query config get user -h "$host")
  else
    login=$(hub::gh_query api --hostname "$host" user --jq .login)
  fi
  [[ -n $login ]] \
    || hub::die "could not determine your GitHub login for $host (run: gh auth login -h $host)"
  printf '%s\n' "$login"
}

# hub::protocol [HOST] : ssh when gh's git_protocol for HOST is ssh, else (gh missing too) https.
hub::protocol() {
  # Without gh, bash's "command not found" goes to /dev/null too, and the answer is empty.
  if [[ $(gh config get git_protocol -h "${1:-$(hub::host)}" 2>/dev/null) == ssh ]]; then
    printf '%s\n' ssh
  else
    printf '%s\n' https
  fi
}

# hub::clone_url HOST OWNER REPO [PROTOCOL] : its https or ssh URL (no PROTOCOL: hub::protocol).
hub::clone_url() {
  local user=git protocol=${4:-$(hub::protocol "$1")}
  if [[ $protocol != ssh ]]; then
    printf 'https://%s/%s/%s.git\n' "$1" "$2" "$3"
    return 0
  fi
  # GitHub Enterprise Cloud's ssh user is the tenant.
  [[ ${1,,} != *.ghe.com ]] || user=${1%%.*}
  printf '%s@%s:%s/%s.git\n' "$user" "$1" "$2" "$3"
}

# hub::is_owner WORD : WORD reads as a GitHub user or organization (a managed user: NAME_SHORTCODE).
hub::is_owner() { [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]*(_[A-Za-z0-9]+)?$ ]]; }

# hub::is_shorthand WORD : WORD reads as OWNER/REPO or REPO.
hub::is_shorthand() {
  local repo=${1#*/}
  if [[ $1 == */* ]]; then
    hub::is_owner "${1%%/*}" && [[ $repo =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  else
    # Alone, REPO must not read as an option.
    [[ $1 =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]] || return 1
  fi
  [[ $repo != . && $repo != .. ]]
}

# hub::local_source WORD [bundle] : git would read WORD as a local repository (or bundle).
hub::local_source() {
  # git tries STR, STR/.git, STR.git/.git (a work tree) and STR.git.
  [[ -e $1 ]] || git rev-parse --resolve-git-dir "$1.git" >/dev/null 2>&1 \
    || git rev-parse --resolve-git-dir "$1.git/.git" >/dev/null 2>&1 \
    || [[ ${2-} == bundle && -f $1.bundle ]]
}

# hub::fetch_source HOST OWNER REPO : the remote that fetches that repository, else its URL.
hub::fetch_source() {
  local found
  if found=$(_hub_core_find_remote "$1 $2 $3"); then
    printf '%s\n' "${found%% *}"
  else
    hub::clone_url "$1" "$2" "$3"
  fi
}

# hub::pull_url WORD : WORD is the URL of a pull request or of one of its pages; sets HUB_URL.
hub::pull_url() {
  hub::parse_github_url "$1" && [[ ${HUB_URL[kind]} == pull && -n ${HUB_URL[number]-} ]]
}

# hub::patch_url WORD : WORD is a pull, commit or comparison URL served as a patch; sets HUB_URL.
hub::patch_url() {
  local page='^https?://[^/?#]+/[^/?#]+/[^/?#]+/pull/[0-9]+(\.(patch|diff)|/[^/?#]*)?/?([?#]|$)'
  hub::parse_github_url "$1" || return 1
  case ${HUB_URL[kind]} in
    # A deeper page, such as pull/N/files/SHA, shows only some of the pull request's changes.
    pull) [[ -n ${HUB_URL[number]-} ]] && [[ -n ${HUB_URL[sha]-} || $1 =~ $page ]] ;;
    # hub::parse_github_url has checked the commit's sha.
    commit) ;;
    # compare/BRANCH (GitHub's "Compare & pull request" link) has no range to download, and the
    # API compares BASE...HEAD only (ref names cannot contain '..', so A..B is the two-dot form).
    compare) [[ ${HUB_URL[range]-} == *...* ]] ;;
    *) return 1 ;;
  esac
}

# hub::download_patches FORMAT INDEXES ARGS... : sets HUB_ARGS to ARGS, URLs at INDEXES as files.
hub::download_patches() {
  local format=$1 indexes=$2 tmp i n=0 endpoint escape rc
  shift 2
  HUB_ARGS=("$@")
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/hub-$HUB_COMMAND.XXXXXX") || exit 1
  # shellcheck disable=SC2064  # the path is expanded now, quoted
  trap "rm -rf -- $(printf '%q' "$tmp")" EXIT
  for i in $indexes; do
    hub::patch_url "${HUB_ARGS[i]}" || continue
    endpoint=repos/${HUB_URL[owner]}/${HUB_URL[repo]}
    if [[ -n ${HUB_URL[sha]-} ]]; then
      endpoint+=/commits/${HUB_URL[sha]}
    elif [[ ${HUB_URL[kind]} == pull ]]; then
      endpoint+=/pulls/${HUB_URL[number]}
    else
      endpoint+=/compare/${HUB_URL[range]}
    fi
    hub::require_gh
    ((n += 1))
    # Newer gh drops terminal escape sequences from its output unless asked to keep them.
    [[ -n ${escape+set} ]] \
      || escape=$(gh api --help 2>/dev/null | grep -o -m 1 -- --allow-escape-sequences)
    gh api --hostname "${HUB_URL[host]}" "$endpoint" -H "Accept: application/vnd.github.$format" \
      ${escape:+"$escape"} >"$tmp/$n.$format" || {
      rc=$?
      _hub_core_say "could not download: $(hub::shown "${HUB_ARGS[i]}")"
      exit "$rc"
    }
    HUB_ARGS[i]=$tmp/$n.$format
  done
}

# _hub_core_entry VALUED WORD : WORD is one of VALUED's entries (an -X= entry is no option word).
_hub_core_entry() { [[ $2 != *[[:space:]=]* && " $1 " == *" $2 "* ]]; }

# _hub_core_cluster VALUED WORD : sets HUB_FLAGS and HUB_REST, WORD split at its first value letter.
_hub_core_cluster() {
  local j
  # An -X= entry is a letter whose value can only be attached (-S[key]): it ends the flags too.
  for ((j = 1; j < ${#2}; j++)); do
    [[ " $1 " != *" -${2:j:1} "* && " $1 " != *" -${2:j:1}= "* ]] || break
  done
  HUB_FLAGS=${2:1:j-1} HUB_REST=${2:j}
}

# hub::takes_value VALUED WORD : git reads the next word as WORD's value (-b, --dep, -qb).
hub::takes_value() {
  local long
  ! _hub_core_entry "$1" "$2" || return 0
  case $2 in
    --) ;;
    --*) for long in $1; do [[ $long != "$2"?* ]] || return 0; done ;;
    -?*)
      _hub_core_cluster "$1" "$2"
      ((${#HUB_REST} == 1)) && [[ " $1 " == *" -$HUB_REST "* ]] && return 0
      ;;
  esac
  return 1
}

# hub::drop_flag LETTER VALUED ARGS... : sets HUB_ARGS to ARGS without -LETTER; fails without it.
hub::drop_flag() {
  local letter=$1 table=$2 word i found=1
  shift 2
  local -a args=("$@")
  HUB_ARGS=()
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    case $word in
      -- | --end-of-options)
        HUB_ARGS+=("${args[@]:i}")
        break
        ;;
      -[!-]*)
        _hub_core_cluster "$table" "$word"
        # Only among letters: -p-x would become --x.
        if [[ $HUB_FLAGS == *"$letter"* && $HUB_FLAGS =~ ^[A-Za-z0-9]+$ ]]; then
          found=0 word=-${HUB_FLAGS//"$letter"/}$HUB_REST
          [[ $word != - ]] || continue
        fi
        ;;
    esac
    HUB_ARGS+=("$word")
    # An option's value stays as given (-o -p).
    if hub::takes_value "$table" "$word" && ((i + 1 < $#)); then HUB_ARGS+=("${args[++i]}"); fi
  done
  return "$found"
}

# hub::scan VALUED ARGS... : sets HUB_OPERANDS and HUB_OPTIONS; VALUED's -X= takes -Xvalue only.
hub::scan() {
  local table=$1 word i
  shift
  local -a args=("$@")
  HUB_OPERANDS=() HUB_OPTIONS=()
  # Help, and a line hub cannot read with certainty, go to git as given.
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    # The option words, -- and --end-of-options included.
    [[ $word != -?* ]] || HUB_OPTIONS+=("$i")
    if hub::takes_value "$table" "$word"; then
      # hub reads only an exact entry: git would expand --dep, and -qb is unclear.
      if ! _hub_core_entry "$table" "$word" || ((i + 1 == $#)); then
        hub::exec_git "$HUB_COMMAND" "$@"
      fi
      ((i += 1))
      continue
    fi
    case $word in
      # git reads every word after either as an operand, -- included after --end-of-options.
      -- | --end-of-options) for ((i += 1; i < $#; i++)); do HUB_OPERANDS+=("$i"); done ;;
      --help | --help-all) hub::exec_git "$HUB_COMMAND" "$@" ;;
      --*) ;;
      -?*)
        _hub_core_cluster "$table" "$word"
        # -h among the flags is git's usage; a value letter after a flag (-qbmain) is unclear.
        [[ $HUB_FLAGS != *h* ]] || hub::exec_git "$HUB_COMMAND" "$@"
        [[ -z $HUB_FLAGS || -z $HUB_REST || " $table " == *" -${HUB_REST::1}= "* ]] \
          || hub::exec_git "$HUB_COMMAND" "$@"
        ;;
      *) HUB_OPERANDS+=("$i") ;;
    esac
  done
}

# hub::gh_subcommand ARGS... : sets HUB_ARGS to ARGS with show as view, list for no subcommand.
hub::gh_subcommand() {
  local -a args=("$@")
  local i=0 help=0
  while ((i < $#)); do
    case ${args[i]} in
      -R | --repo)
        [[ ${args[i + 1]-} != -h && ${args[i + 1]-} != --help ]] || help=1
        ((i += 2))
        ;;
      -R?* | --repo=*) ((i += 1)) ;;
      *) break ;;
    esac
  done
  # gh prints its help for -R --help, but refuses the value when a subcommand follows.
  ((! help || i < $#)) || return 1
  HUB_ARGS=("$@")
  # A -R without its value: gh says so.
  ((i <= $#)) || return 0
  HUB_ARGS=("${args[@]:0:i}")
  case ${args[i]-} in
    -h | --help) return 1 ;;
    show) HUB_ARGS+=(view) ;;
    -*) HUB_ARGS+=(list "${args[i]}") ;;
    *) if ((i < $#)); then HUB_ARGS+=("${args[i]}"); else HUB_ARGS+=(list); fi ;;
  esac
  HUB_ARGS+=("${args[@]:i+1}")
}

# hub::normalize_opts SHORT_VALUED LONG_VALUED ARGS... : sets HUB_ARGS to ARGS, values detached.
hub::normalize_opts() {
  local short=$1 long=" $2 " word head i
  shift 2
  HUB_ARGS=()
  while (($#)); do
    word=$1 && shift
    case $word in
      --) HUB_ARGS+=(-- "$@") && return 0 ;;
      --*=*)
        if [[ $long == *" ${word%%=*} "* ]]; then
          HUB_ARGS+=("${word%%=*}" "${word#*=}")
        else
          HUB_ARGS+=("$word")
        fi
        ;;
      --*)
        HUB_ARGS+=("$word")
        if [[ $long == *" $word "* ]] && (($#)); then HUB_ARGS+=("$1") && shift; fi
        ;;
      -?*)
        head=${word:1}
        [[ -z $short ]] || head=${head%%["$short"]*}
        # Letters only up to the value: split, -u- would end in the word --.
        if [[ $head == *[!A-Za-z0-9]* ]]; then
          HUB_ARGS+=("$word")
          continue
        fi
        for ((i = 1; i < ${#word}; i++)); do
          HUB_ARGS+=("-${word:i:1}")
          [[ -n $short && $short == *"${word:i:1}"* ]] || continue
          if ((i + 1 < ${#word})); then
            HUB_ARGS+=("${word:i+1}")
          elif (($#)); then
            HUB_ARGS+=("$1") && shift
          fi
          break
        done
        ;;
      *) HUB_ARGS+=("$word") ;;
    esac
  done
}

# hub::url_escape WORD : WORD percent-encoded, except A-Za-z0-9._~/:@-.
hub::url_escape() {
  local LC_ALL=C out='' char i
  for ((i = 0; i < ${#1}; i++)); do
    char=${1:i:1}
    [[ $char == [A-Za-z0-9._~/:@-] ]] || printf -v char '%%%02X' "'$char"
    out+=$char
  done
  printf '%s\n' "$out"
}

# hub::show_url PRINT COPY URL : print URL (PRINT 1), copy it (COPY 1), else open it unless printed.
hub::show_url() {
  if (($1)); then printf '%s\n' "$3"; fi
  if (($2)); then
    hub::copy "$3"
  elif ((! $1)); then
    hub::open_url "$3"
  fi
}

# hub::open_url URL : open URL in the browser; the browser's status.
hub::open_url() {
  local browser=${GH_BROWSER:-${BROWSER-}}
  if [[ ${HUB_NOOP-} == 1 ]]; then
    hub::quote open "$1"
  elif [[ -n $browser ]]; then
    eval "$browser"' "$1"'
  elif command -v open >/dev/null; then
    open "$1"
  elif command -v xdg-open >/dev/null; then
    xdg-open "$1"
  else
    hub::die "no browser found to open $1 (set GH_BROWSER or BROWSER)"
  fi
}

# hub::copy TEXT : put TEXT on the clipboard; the tool's status.
hub::copy() {
  if [[ ${HUB_NOOP-} == 1 ]]; then
    hub::quote copy "$1"
  elif command -v pbcopy >/dev/null; then
    printf '%s' "$1" | pbcopy
  elif command -v wl-copy >/dev/null; then
    printf '%s' "$1" | wl-copy
  elif command -v xclip >/dev/null; then
    printf '%s' "$1" | xclip -selection clipboard
  else
    hub::die 'no clipboard tool found (install pbcopy, wl-copy or xclip)'
  fi
}
