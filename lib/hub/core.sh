# shellcheck shell=bash
# shellcheck disable=SC2034  # HUB_* result variables are set here and read by modules
# Summary: Shared helpers of hub's modules.
#
# Sourced by bin/hub with HUB_ROOT, HUB_LIB and HUB_COMMAND set. A helper prints its answer on
# stdout and returns non-zero when it has none, unless its contract names a global it sets.

HUB_ARGS=() HUB_OPERANDS=()
declare -gA HUB_URL=()
unset HUB_GH_ESCAPE
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
hub::remote_exists() { git remote get-url -- "$1" >/dev/null 2>&1; }

# hub::valid_remote_name NAME : NAME can name a remote.
hub::valid_remote_name() { [[ $1 != -* ]] && git check-ref-format "refs/remotes/$1/HEAD"; }

# hub::default_branch HOST OWNER REPO [REMOTE] : the repository's default branch.
hub::default_branch() {
  local ref head=refs/remotes/${4-}/
  if [[ -n ${4-} ]] && ref=$(git symbolic-ref --quiet "${head}HEAD" 2>/dev/null) \
    && [[ $ref == "$head"?* ]] && git show-ref --verify --quiet "$ref"; then
    printf '%s\n' "${ref#"$head"}" && return 0
  fi
  ref=$(hub::gh_query repo view "$1/$2/$3" --json defaultBranchRef --jq .defaultBranchRef.name)
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
  local branch=$1 remote ref host owner repo login
  local -a remotes mine=()
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
    login=$(hub::login "$host" 2>/dev/null) || continue
    [[ ${owner,,} != "${login,,}" ]] || mine+=("$remote")
  done
  if ((${#mine[@]} == 1)); then
    printf '%s\n' "${mine[0]}"
  elif hub::remote_exists origin; then
    printf '%s\n' origin
  else
    return 1
  fi
}

# hub::pushed BRANCH REMOTE : 0 pushed; 1 no REMOTE/BRANCH; 2 and the count of unpushed commits.
hub::pushed() {
  local ref=refs/remotes/$2/$1
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

# hub::host : the default host: GH_HOST, else the only gh host, else github.com.
hub::host() {
  local -a hosts
  [[ -n ${GH_HOST-} ]] && printf '%s\n' "$GH_HOST" && return 0
  mapfile -t hosts < <(hub::gh_hosts)
  if ((${#hosts[@]} == 1)); then
    printf '%s\n' "${hosts[0]}"
  else
    printf '%s\n' github.com
  fi
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
  local url=$1 host path owner repo ssh=0
  case $url in
    https://* | http://* | git://*) url=${url#*://} ;;
    ssh://* | git+ssh://* | ssh+git://*) url=${url#*://} ssh=1 ;;
    *://*) return 1 ;;
    # scp-like only with no / before the first colon: git reads anything else as a path.
    *:*) if [[ ${url%%:*} != */* ]]; then url=${url/:/\/} ssh=1; else return 1; fi ;;
    *) return 1 ;;
  esac
  host=${url%%/*} path=${url#*/}
  host=${host##*@} && host=${host%%:*} && host=${host,,}
  path=${path%/} && path=${path%.git}
  # The host may go to ssh -G: it must not read as an option.
  [[ $host =~ ^[a-z0-9_][a-z0-9_.-]*$ ]] || return 1
  [[ $path =~ ^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9_.-]+)$ ]] || return 1
  owner=${BASH_REMATCH[1]} repo=${BASH_REMATCH[2]}
  [[ $repo != . && $repo != .. ]] || return 1
  if ((ssh)) && ! hub::known_host "$host"; then
    host=$(ssh -G "$host" 2>/dev/null | awk '$1 == "hostname" { print tolower($2); exit }')
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

# hub::parse_project STR : "HOST OWNER REPO" of OWNER/REPO, HOST/OWNER/REPO or a URL.
hub::parse_project() {
  local a b c
  if [[ $1 == *:* ]]; then
    hub::parse_url "$1"
    return
  fi
  [[ $1 =~ ^[^/[:space:]]+(/[^/[:space:]]+){1,2}$ ]] || return 1
  IFS=/ read -r a b c <<<"$1"
  [[ -n $c ]] && printf '%s %s %s\n' "${a,,}" "$b" "$c" && return 0
  printf '%s %s %s\n' "$(hub::host)" "$a" "$b"
}

# hub::parse_github_url URL : HUB_URL (host owner repo kind number sha format range) of a web URL.
hub::parse_github_url() {
  local host path
  local -a part
  HUB_URL=()
  [[ $1 =~ ^https?://([^/?#]+)/([^?#]*) ]] || return 1
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
    pull) [[ ${part[4]-} != commits ]] || HUB_URL[sha]=${part[5]-} ;;
    commit) HUB_URL[sha]=${part[3]-} ;;
    compare) HUB_URL[range]=${path#*/*/compare/} ;;
  esac
  [[ -z ${HUB_URL[sha]+set} || ${HUB_URL[sha]} =~ ^[0-9a-fA-F]{4,64}$ ]]
}

# hub::login [HOST] : your login on HOST (default: hub::host).
hub::login() {
  local host=${1:-$(hub::host)} login=
  # A token variable overrides gh's stored account, whose cached user may be someone else.
  if [[ -z ${GH_TOKEN-}${GITHUB_TOKEN-}${GH_ENTERPRISE_TOKEN-}${GITHUB_ENTERPRISE_TOKEN-} ]]; then
    login=$(hub::gh_query config get user -h "$host")
  fi
  [[ -n $login ]] || login=$(hub::gh_query api --hostname "$host" user --jq .login)
  [[ -n $login ]] \
    || hub::die "could not determine your GitHub login for $host (run: gh auth login -h $host)"
  printf '%s\n' "$login"
}

# hub::protocol [HOST] : ssh when gh's git_protocol for HOST is ssh, else https.
hub::protocol() {
  if [[ $(hub::gh_query config get git_protocol -h "${1:-$(hub::host)}") == ssh ]]; then
    printf '%s\n' ssh
  else
    printf '%s\n' https
  fi
}

# hub::clone_url HOST OWNER REPO [PROTOCOL] : the repository's https (default) or ssh URL.
hub::clone_url() {
  local user=git
  if [[ ${4-} != ssh ]]; then
    printf 'https://%s/%s/%s.git\n' "$1" "$2" "$3"
    return 0
  fi
  # GitHub Enterprise Cloud's ssh user is the tenant.
  [[ ${1,,} != *.ghe.com ]] || user=${1%%.*}
  printf '%s@%s:%s/%s.git\n' "$user" "$1" "$2" "$3"
}

# hub::is_shorthand STR : STR reads as OWNER/REPO or REPO.
hub::is_shorthand() {
  [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9-]*/([A-Za-z0-9_.-]+)$ ]] \
    || [[ $1 =~ ^([A-Za-z0-9_.][A-Za-z0-9_.-]*)$ ]] || return 1
  [[ ${BASH_REMATCH[1]} != . && ${BASH_REMATCH[1]} != .. ]]
}

# hub::local_source STR [bundle] : git would read STR as a local repository (or bundle).
hub::local_source() {
  [[ -e $1 ]] || git rev-parse --resolve-git-dir "$1.git" >/dev/null 2>&1 \
    || [[ ${2-} == bundle && -f $1.bundle ]]
}

# hub::fetch_source HOST OWNER REPO : the remote that fetches that repository, else its URL.
hub::fetch_source() {
  local found
  if found=$(_hub_core_find_remote "$1 $2 $3"); then
    printf '%s\n' "${found%% *}"
  else
    hub::clone_url "$1" "$2" "$3" "$(hub::protocol "$1")"
  fi
}

# hub::fetch_patch URL FORMAT FILE : download a pull, commit or compare URL as patch or diff.
hub::fetch_patch() {
  local endpoint
  hub::parse_github_url "$1" || return 1
  endpoint=repos/${HUB_URL[owner]}/${HUB_URL[repo]}
  case ${HUB_URL[kind]}:${HUB_URL[sha]-}:${HUB_URL[number]-}:${HUB_URL[range]-} in
    pull:?*:*:* | commit:?*:*:*) endpoint+=/commits/${HUB_URL[sha]} ;;
    pull::?*:*) endpoint+=/pulls/${HUB_URL[number]} ;;
    compare:*:*:?*) endpoint+=/compare/${HUB_URL[range]} ;;
    *) return 1 ;;
  esac
  hub::require_gh
  # Newer gh drops terminal escape sequences from its output unless asked to keep them.
  [[ -n ${HUB_GH_ESCAPE+set} ]] \
    || HUB_GH_ESCAPE=$(gh api --help 2>/dev/null | grep -o -m 1 -- --allow-escape-sequences)
  gh api --hostname "${HUB_URL[host]}" "$endpoint" -H "Accept: application/vnd.github.$2" \
    ${HUB_GH_ESCAPE:+"$HUB_GH_ESCAPE"} >"$3"
}

# hub::scan VALUED ARGS... : HUB_OPERANDS, the operands' indexes in ARGS; unclear lines go to git.
hub::scan() {
  local valued=" $1 " word long i j
  shift
  local -a args=("$@")
  HUB_OPERANDS=()
  for ((i = 0; i < $#; i++)); do
    word=${args[i]}
    case $word in
      # git reads every word after either as an operand, -- included after --end-of-options.
      -- | --end-of-options) for ((i += 1; i < $#; i++)); do HUB_OPERANDS+=("$i"); done ;;
      --help) hub::exec_git "$HUB_COMMAND" "$@" ;;
      --*=*) ;;
      --*)
        if [[ $valued == *" $word "* ]]; then
          ((i + 1 < $#)) || hub::exec_git "$HUB_COMMAND" "$@"
          ((i += 1)) && continue
        fi
        # git would expand an abbreviation such as --dep to --depth.
        for long in $valued; do
          [[ $long != "$word"?* ]] || hub::exec_git "$HUB_COMMAND" "$@"
        done
        ;;
      -?*)
        if [[ $valued == *" ${word:0:2} "* ]]; then
          ((${#word} > 2 || i + 1 < $#)) || hub::exec_git "$HUB_COMMAND" "$@"
          ((${#word} > 2)) || ((i += 1))
          continue
        fi
        for ((j = 2; j < ${#word}; j++)); do
          [[ $valued != *" -${word:j:1} "* ]] || hub::exec_git "$HUB_COMMAND" "$@"
        done
        ;;
      *) HUB_OPERANDS+=("$i") ;;
    esac
  done
}

# hub::gh_subcommand ARGS... : HUB_ARGS, ARGS with show as view and list for no subcommand.
hub::gh_subcommand() {
  local -a args=("$@")
  local i=0
  while ((i < $#)); do
    case ${args[i]} in
      -R | --repo) ((i += 2)) ;;
      -R?* | --repo=*) ((i += 1)) ;;
      *) break ;;
    esac
  done
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

# hub::normalize_opts SHORT_VALUED LONG_VALUED ARGS... : HUB_ARGS, clusters split, values detached.
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

# hub::url_escape STR : STR percent-encoded, except A-Za-z0-9._~/:@-.
hub::url_escape() {
  local LC_ALL=C out='' char i
  for ((i = 0; i < ${#1}; i++)); do
    char=${1:i:1}
    [[ $char == [A-Za-z0-9._~/:@-] ]] || printf -v char '%%%02X' "'$char"
    out+=$char
  done
  printf '%s\n' "$out"
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
