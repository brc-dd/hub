# shellcheck shell=bash
# shellcheck disable=SC2034  # HUB_* result variables are set here and read by modules
# shellcheck disable=SC2153  # HUB_ROOT is exported by bin/hub
# core.sh — helpers shared by all modules; sourced by bin/hub after git has re-entered it.
#
# A module lib/hub/{cmd,ext}/<name>.sh defines hub_cmd_<name> or hub_ext_<name>; its header
# comment is its manual. Side effects go through hub::git / hub::gh / hub::exec_* so --noop can
# print them; read-only lookups use hub::git_query / hub::gh_query. Results a helper returns by
# side effect are HUB_* variables named on the helper.
#
# git's global options were applied by git itself before this code runs: their effect is in the
# environment (GIT_DIR, GIT_WORK_TREE, GIT_CONFIG_PARAMETERS, GIT_PAGER, ...), which every git and
# gh started from here inherits. HUB_GIT_GLOBALS holds them only to print faithful command lines.

[[ -n ${HUB_CORE_LOADED:-} ]] && return 0
HUB_CORE_LOADED=1

# The version lives in the VERSION file at the project root (script/bump maintains it).
if [[ -z ${HUB_VERSION:-} ]]; then
  if [[ -r $HUB_ROOT/VERSION ]]; then read -r HUB_VERSION <"$HUB_ROOT/VERSION"; else HUB_VERSION=unknown; fi
fi
: "${HUB_NOOP:=0}"
declare -p HUB_GIT_GLOBALS >/dev/null 2>&1 || HUB_GIT_GLOBALS=()

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
# hub::quote ARGS... : one line, shell-quoted only where needed (for --noop output). The same
# rule as hub_quote in bin/hub: a literal ~ is quoted, since the shell would expand it.
hub::quote() {
  local out='' arg
  for arg in "$@"; do
    [[ $arg =~ ^[A-Za-z0-9_./:@%+=,^-]+$ ]] || printf -v arg '%q' "$arg"
    out+="${out:+ }$arg"
  done
  printf '%s\n' "$out"
}

# hub::git_line ARGS... : the `git ...` line as the user would type it, with the global options
# they gave hub in front (for --noop and debug output).
hub::git_line() { hub::quote git "${HUB_GIT_GLOBALS[@]}" "$@"; }

# hub::run CMD ARGS... : run a command with side effects; under --noop, print it instead.
hub::run() {
  if ((HUB_NOOP)); then
    hub::quote "$@"
    return 0
  fi
  hub::debug "\$ $(hub::quote "$@")"
  "$@"
}

# hub::git ARGS... : run git (printed under --noop). The global options given to hub are in
# effect through the environment git exported.
hub::git() {
  if ((HUB_NOOP)); then
    hub::git_line "$@"
    return 0
  fi
  hub::debug "\$ $(hub::git_line "$@")"
  git "$@"
}

# hub::git_query ARGS... : read-only git call; always runs, stderr silenced.
hub::git_query() { git "$@" 2>/dev/null; }

# hub::exec_git ARGS... : hand the process over to git (printed under --noop, then exit 0).
hub::exec_git() {
  if ((HUB_NOOP)); then
    hub::git_line "$@"
    exit 0
  fi
  hub::debug "\$ $(hub::git_line "$@")"
  exec git "$@"
}

hub::require_gh() {
  command -v gh >/dev/null 2>&1 || hub::die "hub: this command needs the GitHub CLI (gh): https://cli.github.com"
}

# hub::git_env : the environment git exported for the global options hub was given
# (HUB_GIT_GLOBALS), as NAME=VALUE words quoted for a shell, in HUB_GIT_ENV, so that a printed gh
# line runs with the context the real one had: GIT_CONFIG_PARAMETERS for -c and --config-env, in
# git's own quoting ('key'='value'), after whatever GIT_CONFIG_PARAMETERS gh inherited from before
# the command line (the user's, or an outer git's), carried along as
# "${GIT_CONFIG_PARAMETERS:+$GIT_CONFIG_PARAMETERS }" when there was one, never printed; a
# --config-env value as the variable it came from, quoted the way git quotes it when the line runs
# ($(git rev-parse --sq-quote "$VAR" | cut -c2-), through printenv for a name the shell cannot
# expand), never as its value, since the user kept it off the command line; GIT_DIR,
# GIT_WORK_TREE, GIT_NAMESPACE, GIT_ATTR_SOURCE and GIT_EXEC_PATH as gh has them; and the switches
# (--literal-pathspecs, --no-replace-objects, --no-optional-locks, ...) as git sets them. -C needs
# none (hub::gh_line prints a cd), and the pager options export nothing gh reads.
hub::git_env() {
  local -a g=("${HUB_GIT_GLOBALS[@]}") names=()
  local i arg kv entry params='' given=0 name key var
  HUB_GIT_ENV=()
  for ((i = 0; i < ${#g[@]}; i++)); do
    arg=${g[i]} name=''
    case $arg in
      -c)
        kv=${g[++i]-} # key=value, split at the first =, as git splits it; a key alone is 'key'= (true)
        if [[ $kv == *=* ]]; then
          entry="$(hub::sq "${kv%%=*}")=$(hub::sq "${kv#*=}")"
        else
          entry="$(hub::sq "$kv")="
        fi
        params+="${params:+ }$(hub::dquote_text "$entry")"
        ((++given))
        name=GIT_CONFIG_PARAMETERS
        ;;
      --config-env | --config-env=*)
        if [[ $arg == *=* ]]; then kv=${arg#*=}; else kv=${g[++i]-}; fi
        key=${kv%=*} var=${kv##*=} # split at the last =, as git splits it
        if [[ $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          var="\$$var"
        else # a name the shell cannot expand (CONFIG.VAR): printenv reads it, as git did
          var="\$(printenv $(hub::quote "$var"))"
        fi
        params+="${params:+ }$(hub::dquote_text "$(hub::sq "$key")")=\$(git rev-parse --sq-quote \"$var\" | cut -c2-)"
        ((++given))
        name=GIT_CONFIG_PARAMETERS
        ;;
      -C | --shallow-file | --super-prefix) ((++i)) ;;                  # -C becomes a cd; the others export nothing
      --git-dir | --work-tree | --namespace | --attr-source) ((++i)) ;& # the value is the next argument
      --git-dir=* | --work-tree=* | --namespace=* | --attr-source=*)
        case ${arg%%=*} in
          --git-dir) name=GIT_DIR ;;
          --work-tree) name=GIT_WORK_TREE ;;
          --namespace) name=GIT_NAMESPACE ;;
          --attr-source) name=GIT_ATTR_SOURCE ;;
        esac
        ;;
      --bare) names+=(GIT_DIR) name=GIT_IMPLICIT_WORK_TREE ;;
      --exec-path=*) name=GIT_EXEC_PATH ;;
      --literal-pathspecs | --no-literal-pathspecs) name=GIT_LITERAL_PATHSPECS ;;
      --glob-pathspecs) name=GIT_GLOB_PATHSPECS ;;
      --noglob-pathspecs) name=GIT_NOGLOB_PATHSPECS ;;
      --icase-pathspecs) name=GIT_ICASE_PATHSPECS ;;
      --no-replace-objects) name=GIT_NO_REPLACE_OBJECTS ;;
      --no-lazy-fetch) name=GIT_NO_LAZY_FETCH ;;
      --no-optional-locks) name=GIT_OPTIONAL_LOCKS ;;
      --no-advice) name=GIT_ADVICE ;;
    esac
    [[ -z $name ]] || names+=("$name")
  done
  local -A seen=()
  for name in "${names[@]}"; do
    [[ -z ${seen[$name]-} ]] || continue
    seen[$name]=1
    if [[ $name == GIT_CONFIG_PARAMETERS ]]; then
      # gh inherited hub's own GIT_CONFIG_PARAMETERS: whatever stood there before git read the
      # command line, then the command line's entries; the line carries the former along
      (($(hub::config_entries "${GIT_CONFIG_PARAMETERS-}") <= given)) \
        || params="\${GIT_CONFIG_PARAMETERS:+\$GIT_CONFIG_PARAMETERS }$params"
      HUB_GIT_ENV+=("GIT_CONFIG_PARAMETERS=\"$params\"")
    elif [[ -n ${!name+x} ]]; then
      HUB_GIT_ENV+=("$(hub::quote "$name=${!name}")")
    fi
  done
}

# hub::config_entries TEXT : how many entries TEXT holds, GIT_CONFIG_PARAMETERS as git writes it
# ('key'='value' 'key'= ...): whitespace separates the entries, except inside the quotes, and
# outside them a backslash quotes one character ('\'' and '\!' stand for a quote and a !).
hub::config_entries() {
  local s=$1 i c n=0 quoted=0 entry=0
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if ((quoted)); then
      [[ $c != \' ]] || quoted=0
    elif [[ $c == \' ]]; then
      quoted=1 entry=1
    elif [[ $c == \\ ]]; then
      ((i++)) || true
      entry=1
    elif [[ $c == [[:space:]] ]]; then
      if ((entry)); then n=$((n + 1)) entry=0; fi
    else
      entry=1
    fi
  done
  ((entry)) && n=$((n + 1))
  printf '%s\n' "$n"
}

# hub::sq TEXT : TEXT in single quotes, as git quotes the entries of GIT_CONFIG_PARAMETERS: a quote
# and a ! stand outside the quotes, as '\'' and '\!'.
hub::sq() {
  local s=$1 q=\'
  s=${s//$q/$q\\$q$q}
  s=${s//!/$q\\!$q}
  printf "'%s'\n" "$s"
}

# hub::dquote_text TEXT : TEXT escaped for the inside of a double-quoted shell word.
hub::dquote_text() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//\$/\\\$}
  s=${s//\`/\\\`}
  printf '%s\n' "$s"
}

# hub::gh_line WORDS... : a gh command line as the user could run it (for --noop and debug output):
# WORDS is `gh ...`, or `env VAR=VALUE gh ...`. gh takes none of git's global options; what they
# put in the environment, which gh and its git children inherit, is printed as an env prefix
# (hub::git_env). gh has no -C: when git's -C made hub run in another directory than the one it
# was started in, the line is `(cd DIR && gh ...)`.
hub::gh_line() {
  local -a words
  local line
  hub::git_env
  words=("${HUB_GIT_ENV[@]}")
  if [[ $1 == env ]]; then
    shift
    while [[ ${1-} == [A-Za-z_]*=* ]]; do
      words+=("$(hub::quote "$1")")
      shift
    done
  fi
  line=$(hub::quote "$@")
  ((${#words[@]} == 0)) || line="env ${words[*]} $line"
  if [[ -n ${HUB_INVOKED_PWD-} && ! $PWD -ef $HUB_INVOKED_PWD ]]; then
    printf '(cd %s && %s)\n' "$(hub::quote "$PWD")" "$line"
  else
    printf '%s\n' "$line"
  fi
}

# hub::gh ARGS... : gh call with side effects (printed under --noop). gh's own git subprocesses
# inherit the same environment as hub's git.
hub::gh() {
  hub::require_gh
  if ((HUB_NOOP)); then
    hub::gh_line gh "$@"
    return 0
  fi
  hub::debug "\$ $(hub::gh_line gh "$@")"
  gh "$@"
}

# hub::gh_query ARGS... : read-only gh call that always runs (used to work out what to do).
hub::gh_query() {
  hub::require_gh
  hub::debug "\$ $(hub::gh_line gh "$@")"
  gh "$@"
}

# hub::exec_gh ARGS... : hand the process over to gh (printed under --noop, then exit 0).
hub::exec_gh() {
  hub::require_gh
  if ((HUB_NOOP)); then
    hub::gh_line gh "$@"
    exit 0
  fi
  hub::debug "\$ $(hub::gh_line gh "$@")"
  exec gh "$@"
}

# ---------------------------------------------------------------------------
# Options of hub-owned commands
# ---------------------------------------------------------------------------
# hub::gh_subcommand_args ARGS... : HUB_ARGS gets the arguments of a gh-backed command with the
# subcommand word mapped (show -> view), or `list` in front when there is none. The word is found
# as gh (cobra) finds it: an option written `-x` or `--long` takes the next argument as its value,
# whatever it looks like; `-xVALUE`, `--long=VALUE`, `-` and an empty argument are not words; `--`
# ends the search. Returns 1 when -h/--help comes before the word: the caller prints its manual.
hub::gh_subcommand_args() {
  local -a opts=()
  local word
  HUB_ARGS=()
  while (($#)); do
    case $1 in
      --) break ;;
      -h | --help) return 1 ;;
      '' | - | --*=* | -[!-]?*) ;;
      --?* | -?)
        opts+=("$1")
        shift
        (($#)) || break
        ;;
      *)
        word=$1
        shift
        [[ $word != show ]] || word=view
        HUB_ARGS=("${opts[@]}" "$word" "$@")
        return 0
        ;;
    esac
    opts+=("$1")
    shift
  done
  HUB_ARGS=(list "${opts[@]}" "$@")
}

# hub::normalize_opts SHORTS LONGS ARGS... : HUB_ARGS gets ARGS with short-option clusters split
# (-pf -> -p -f), attached values detached (-bmain -> -b main, --base=main -> --base main) and
# everything after -- kept as it is. SHORTS lists the short options that take a value ("bhm");
# LONGS the long ones, space-separated ("--base --head"). Unknown options and operands are kept
# as they are, for the caller's case statement to accept or reject. An operand is anything that
# does not start with -, plus - itself.
hub::normalize_opts() {
  local shorts=$1 longs=" $2 " arg name c i
  shift 2
  HUB_ARGS=()
  while (($#)); do
    arg=$1
    shift
    case $arg in
      --)
        HUB_ARGS+=(-- "$@")
        return 0
        ;;
      --*=*)
        name=${arg%%=*}
        if [[ $longs == *" $name "* ]]; then HUB_ARGS+=("$name" "${arg#*=}"); else HUB_ARGS+=("$arg"); fi
        ;;
      --?*) HUB_ARGS+=("$arg") ;;
      -?*)
        for ((i = 1; i < ${#arg}; i++)); do
          c=${arg:i:1}
          if [[ $shorts == *"$c"* ]]; then
            if ((i + 1 < ${#arg})); then
              HUB_ARGS+=("-$c" "${arg:i+1}")
            elif (($#)); then
              HUB_ARGS+=("-$c" "$1")
              shift
            else
              HUB_ARGS+=("-$c") # the caller reports the missing value
            fi
            break
          fi
          HUB_ARGS+=("-$c")
        done
        ;;
      *) HUB_ARGS+=("$arg") ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Options of git commands, as the installed git reads them
# ---------------------------------------------------------------------------
# hub::git_options CMD... : the long options of git CMD (a subcommand too: remote add), one per
# line, as the installed git lists them for its own completion (--git-completion-helper-all), so
# that hub reads a command line the way this git does: an option listed with a trailing = takes a
# value, which is the next argument when it is not attached; the others take none, or only an
# attached one (--log=5). Asked once per run; the answer is also left in HUB_GIT_OPTIONS, for a
# caller that must not read it through a subshell (which would lose the cache). Fails when git
# cannot answer, as outside a repository for a command that needs one; git then fails the same
# way on the command itself.
hub::git_options() {
  local out
  if [[ ${HUB_GIT_OPTIONS_FOR-} != "$*" ]]; then
    out=$(hub::git_query "$@" --git-completion-helper-all) || return 1
    HUB_GIT_OPTIONS_FOR=$*
    # shellcheck disable=SC2086  # one option per word
    HUB_GIT_OPTIONS=$(printf '%s\n' $out)
  fi
  printf '%s\n' "$HUB_GIT_OPTIONS"
}

# hub::git_usage CMD... : the usage git prints for `CMD -h`, asked once per run (also left in
# HUB_GIT_USAGE). Fails when git prints none, as for a subcommand outside a repository.
hub::git_usage() {
  local out
  if [[ ${HUB_GIT_USAGE_FOR-} != "$*" ]]; then
    out=$(git "$@" -h 2>/dev/null) || true # the usage goes to standard output, with status 129
    [[ $out == usage:* ]] || return 1
    HUB_GIT_USAGE_FOR=$* HUB_GIT_USAGE=$out
  fi
  printf '%s\n' "$HUB_GIT_USAGE"
}

# hub::git_short_options CMD... : the short options of git CMD, as a string of their letters, from
# its usage (the completion table lists long options only); also left in HUB_GIT_SHORTS.
hub::git_short_options() {
  local line
  HUB_GIT_SHORTS=''
  hub::git_usage "$@" >/dev/null || return 1
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]+-([^-[:space:],]) ]] && HUB_GIT_SHORTS+=${BASH_REMATCH[1]}
  done <<<"$HUB_GIT_USAGE"
  printf '%s\n' "$HUB_GIT_SHORTS"
}

# hub::git_valued_options CMD... : the long options of git CMD that take a value, required
# (--file <file>) or optional (--log[=<n>]), one name per line without the dashes, from its usage.
# The completion table lists an optional value, and the value an option reads by itself (merge
# --file), as no value at all; the usage tells those from the switches, which refuse --switch=VALUE.
# Also left in HUB_GIT_VALUED.
hub::git_valued_options() {
  local line re='^[[:space:]]+(-[^-[:space:],],[[:space:]])?--(\[no-\])?([A-Za-z0-9-]+)(\[=|[[:space:]][<(.])'
  HUB_GIT_VALUED=''
  hub::git_usage "$@" >/dev/null || return 1
  while IFS= read -r line; do
    [[ $line =~ $re ]] && HUB_GIT_VALUED+=${BASH_REMATCH[3]}$'\n'
  done <<<"$HUB_GIT_USAGE"
  printf '%s' "$HUB_GIT_VALUED"
}

# hub::git_option CMD SHORTS OPTIONAL ARG : how git CMD reads the option ARG (-x, a cluster -xyz,
# --long or --long=VALUE; never -- itself). Sets HUB_OPTS to the options ARG spells, in order and
# as git names them: the long option ARG spells or unambiguously abbreviates (--dep is --depth),
# or every short option of a cluster up to the first that takes a value (-qj3 is -q -j); and
# HUB_OPT_NEXT to 1 when the last of them takes the next argument as its value. SHORTS lists CMD's
# short options whose value is required ("jo"), OPTIONAL those whose value is optional, which git
# reads only attached ("S", for -S[<key-id>]). Returns 1 when git would not take ARG: an unknown
# or ambiguous long option, a value attached to a switch (--detach=1; one attached to an option
# whose usage shows a value, --log=5 or --file=F, is its value), or a short option that CMD's
# usage does not list; git refuses each, so callers leave the command line to it. For cherry-pick
# and revert git keeps unknown long options for its revision parser and takes no abbreviation, so
# only a spelled-out option is known.
hub::git_option() {
  local cmd=$1 shorts=$2 optional=$3 arg=$4 name entry found='' n=0 c i table
  HUB_OPTS=() HUB_OPT_NEXT=0
  if [[ $arg == --* ]]; then
    name=${arg%%=*}
    # shellcheck disable=SC2086  # CMD may be two words
    hub::git_options $cmd >/dev/null || return 1 # not through a subshell: the cache would be lost
    table=$HUB_GIT_OPTIONS
    while IFS= read -r entry; do
      [[ -n $entry && $entry != -- ]] || continue
      if [[ ${entry%=} == "$name" ]]; then
        found=$entry n=1
        break
      fi
      [[ $cmd == cherry-pick || $cmd == revert ]] && continue
      if [[ $entry == "$name"* ]]; then
        found=$entry
        ((++n))
      fi
    done <<<"$table"
    ((n == 1)) || return 1
    HUB_OPTS=("${found%=}")
    if [[ $found == *= ]]; then
      [[ $arg == *=* ]] || HUB_OPT_NEXT=1
    elif [[ $arg == *=* ]]; then
      # shellcheck disable=SC2086  # CMD may be two words
      hub::git_valued_options $cmd >/dev/null || return 1
      [[ $'\n'$HUB_GIT_VALUED == *$'\n'"${found#--}"$'\n'* ]] || return 1 # a switch: git refuses the value
    fi
    return 0
  fi
  # shellcheck disable=SC2086  # CMD may be two words
  hub::git_short_options $cmd >/dev/null || return 1
  for ((i = 1; i < ${#arg}; i++)); do
    c=${arg:i:1}
    [[ $HUB_GIT_SHORTS == *"$c"* ]] || return 1 # an unknown switch, which git refuses
    HUB_OPTS+=("-$c")
    if [[ -n $shorts && $shorts == *"$c"* ]]; then
      ((i + 1 < ${#arg})) || HUB_OPT_NEXT=1
      return 0
    fi
    [[ -n $optional && $optional == *"$c"* ]] && return 0 # the rest of the cluster is its value
  done
  return 0
}

# ---------------------------------------------------------------------------
# Repository
# ---------------------------------------------------------------------------
hub::in_repo() { [[ $(hub::git_query rev-parse --is-inside-work-tree) == true ]]; }
hub::require_repo() { hub::in_repo || hub::die "fatal: not a git repository (or any of the parent directories): .git"; }
hub::git_dir() { hub::git_query rev-parse --git-dir; }
# hub::toplevel : the absolute path of the top of the work tree (modules never cd; they pass this on).
hub::toplevel() { hub::git_query rev-parse --show-toplevel; }

# hub::current_branch : the branch HEAD is on, read as a full ref so that a name git would have to
# disambiguate (heads/topic next to a tag topic) comes back as the branch name. Fails when detached.
hub::current_branch() {
  local ref
  ref=$(hub::git_query symbolic-ref -q HEAD) && [[ $ref == refs/heads/?* ]] || return 1
  printf '%s\n' "${ref#refs/heads/}"
}

# hub::branch_exists NAME : refs/heads/NAME exists.
hub::branch_exists() { hub::git_query show-ref --verify --quiet -- "refs/heads/$1"; }

# hub::valid_remote_name NAME : NAME can name a remote (no leading -, and refs/remotes/NAME/HEAD
# is a well-formed ref).
hub::valid_remote_name() { [[ $1 != -* ]] && hub::git_query check-ref-format "refs/remotes/$1/HEAD"; }

# hub::remote_exists NAME : git knows a remote called NAME (configured, or in the legacy
# .git/remotes and .git/branches files).
hub::remote_exists() { hub::git_query remote get-url -- "$1" >/dev/null; }

# ---------------------------------------------------------------------------
# Hosts and URLs
# ---------------------------------------------------------------------------
# hub::gh_hosts : the hosts gh is logged in to, one per line, read once from gh's hosts.yml. The
# top-level keys of that file are the hosts, bare or quoted, possibly followed by a comment: in
# the block style gh writes, one per line, or in a flow mapping ({host: {user: x}, other: {...}})
# a hand edit may have left, which is read by nesting depth.
hub::gh_hosts() {
  if [[ -z ${HUB_GH_HOSTS+x} ]]; then
    HUB_GH_HOSTS=''
    local file=${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml line text=''
    if [[ -r $file ]]; then
      while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*(#|---[[:space:]]*$|$) ]] && continue # comments, the document marker
        text+=$line$'\n'
      done <"$file"
      if [[ $text == \{* ]]; then
        _hub_gh_hosts_flow "$text"
      else
        while IFS= read -r line; do
          [[ $line =~ ^(\"([A-Za-z0-9.:-]+)\"|\'([A-Za-z0-9.:-]+)\'|([A-Za-z0-9.:-]+)):[[:space:]]*(#.*)?$ ]] || continue
          HUB_GH_HOSTS+="${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"$'\n'
        done <<<"$text"
      fi
    fi
  fi
  printf '%s' "$HUB_GH_HOSTS"
}

# _hub_gh_hosts_flow TEXT : the keys at depth one of a YAML flow mapping, into HUB_GH_HOSTS; a key
# is what stands before the first : of an entry, bare or quoted.
_hub_gh_hosts_flow() {
  local s=$1 c key='' depth=0 in_key=1 quote='' i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ -n $quote ]]; then
      [[ $c == "$quote" ]] && quote=''
      ((depth == 1 && in_key)) && [[ -n $quote ]] && key+=$c
      continue
    fi
    case $c in
      \" | \') quote=$c ;;
      \{ | \[) ((++depth)) ;;
      \} | \]) ((depth--)) ;;
      :)
        if ((depth == 1 && in_key)); then
          key=${key//[[:space:]]/}
          [[ $key =~ ^[A-Za-z0-9.:-]+$ ]] && HUB_GH_HOSTS+=$key$'\n'
          key='' in_key=0
        fi
        ;;
      ,) ((depth == 1)) && key='' in_key=1 ;;
      *) ((depth == 1 && in_key)) && key+=$c ;;
    esac
  done
}

# hub::host : the default GitHub host, following gh's rule: GH_HOST (or hub 2.x's GITHUB_HOST),
# else the only host gh is logged in to, else github.com.
hub::host() {
  if [[ -n ${GH_HOST:-${GITHUB_HOST:-}} ]]; then
    printf '%s\n' "${GH_HOST:-$GITHUB_HOST}"
    return 0
  fi
  local hosts
  hosts=$(hub::gh_hosts)
  if [[ -n $hosts && $hosts != *$'\n'* ]]; then printf '%s\n' "$hosts"; else printf 'github.com\n'; fi
}

# hub::known_hosts : the hosts hub treats as GitHub: github.com, GH_HOST/GITHUB_HOST, every host gh is
# logged in to, and every `git config hub.host` entry. Ports are ignored when hosts are compared.
hub::known_hosts() {
  {
    printf 'github.com\n'
    [[ -n ${GH_HOST:-} ]] && printf '%s\n' "$GH_HOST"
    [[ -n ${GITHUB_HOST:-} ]] && printf '%s\n' "$GITHUB_HOST"
    hub::gh_hosts
    hub::git_query config --get-all hub.host
  } | awk 'NF && !seen[tolower($0)]++'
}

hub::is_known_host() {
  local h want=${1,,}
  want=${want%%:*}
  while IFS= read -r h; do
    h=${h,,}
    [[ ${h%%:*} == "$want" ]] && return 0
  done < <(hub::known_hosts)
  return 1
}

# hub::same_host A B : the same host, ignoring case and port.
hub::same_host() {
  local a=${1,,} b=${2,,}
  [[ ${a%%:*} == "${b%%:*}" ]]
}

# hub::ssh_hostname HOST [USER] [PORT] : the host name ssh would really connect to for HOST, from the
# ssh_config of the ssh git uses (GIT_SSH_COMMAND, core.sshCommand, GIT_SSH, else ssh), asked with
# `ssh -G` for the same user and port so that Match rules see the same connection. Prints nothing
# and fails when that program is not OpenSSH (only ssh answers -G) or ssh fails.
hub::ssh_hostname() {
  local host=$1 user=${2-} port=${3-} cmd prog
  local -a args=(-G)
  [[ $host == -* ]] && return 1
  [[ -n $port ]] && args+=(-p "$port")
  args+=("${user:+$user@}$host")
  cmd=${GIT_SSH_COMMAND:-}
  [[ -n $cmd ]] || cmd=$(hub::git_query config --get core.sshCommand) || cmd=''
  if [[ -n $cmd ]]; then
    read -r prog _ <<<"$cmd"
    [[ ${prog##*/} == ssh ]] || return 1
    sh -c "$cmd \"\$@\"" sh "${args[@]}" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }'
  elif [[ -n ${GIT_SSH:-} ]]; then
    [[ ${GIT_SSH##*/} == ssh ]] || return 1
    "$GIT_SSH" "${args[@]}" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }'
  else
    command -v ssh >/dev/null 2>&1 || return 1
    ssh "${args[@]}" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }'
  fi
}

# hub::parse_remote_url URL : the parts of a git remote URL that names a repository on a GitHub-like
# host. Sets HUB_URL_SCHEME (https, http, ssh or git), HUB_URL_USER (the SSH user, usually git),
# HUB_URL_HOST (lowercased), HUB_URL_PORT, HUB_URL_OWNER and HUB_URL_REPO (without .git). Accepts
# https://, http://, ssh://, git://, git+ssh://, ssh+git:// and scp-like [user@]host:owner/repo[.git];
# the path must be exactly OWNER/REPO[.git][/]. Returns 1 for anything else: local paths, file://,
# other schemes, extra path components.
hub::parse_remote_url() {
  local url=$1 auth rest
  HUB_URL_SCHEME='' HUB_URL_USER='' HUB_URL_HOST='' HUB_URL_PORT='' HUB_URL_OWNER='' HUB_URL_REPO=''
  case $url in
    https://* | http://* | ssh://* | git://* | git+ssh://* | ssh+git://*)
      HUB_URL_SCHEME=${url%%://*}
      case $HUB_URL_SCHEME in git+ssh | ssh+git) HUB_URL_SCHEME=ssh ;; esac
      rest=${url#*://}
      auth=${rest%%/*}
      rest=${rest#"$auth"}
      [[ $auth == *@* ]] && {
        HUB_URL_USER=${auth%%@*}
        HUB_URL_USER=${HUB_URL_USER%%:*}
        auth=${auth#*@}
      }
      HUB_URL_HOST=${auth%%:*}
      [[ $auth == *:* ]] && HUB_URL_PORT=${auth#*:}
      ;;
    *://*) return 1 ;;
    */*:* | *:*) # scp-like, only when no slash precedes the colon
      auth=${url%%:*}
      [[ $auth == */* ]] && return 1
      rest=/${url#*:}
      HUB_URL_SCHEME=ssh
      [[ $auth == *@* ]] && {
        HUB_URL_USER=${auth%%@*}
        auth=${auth#*@}
      }
      HUB_URL_HOST=$auth
      ;;
    *) return 1 ;;
  esac
  while [[ $rest == /* ]]; do rest=${rest#/}; done
  rest=${rest%/}
  [[ $rest == */* ]] || return 1
  HUB_URL_OWNER=${rest%%/*}
  HUB_URL_REPO=${rest#*/}
  [[ $HUB_URL_REPO == */* ]] && return 1
  HUB_URL_REPO=${HUB_URL_REPO%.git}
  HUB_URL_HOST=${HUB_URL_HOST,,}
  [[ -n $HUB_URL_HOST && -n $HUB_URL_OWNER && -n $HUB_URL_REPO && $HUB_URL_PORT =~ ^[0-9]*$ ]]
}

# hub::canonical_host : after hub::parse_remote_url, the GitHub host the URL really names, in
# HUB_URL_HOST: for an SSH URL the host ssh would connect to (an ssh_config alias is resolved, then
# ssh.github.com is github.com); an HTTPS or git URL names its host literally, ssh_config never
# rewrites it. Returns 1 when the result is not a known GitHub host.
hub::canonical_host() {
  local host=$HUB_URL_HOST real
  if [[ $HUB_URL_SCHEME == ssh ]]; then
    if real=$(hub::ssh_hostname "$host" "$HUB_URL_USER" "$HUB_URL_PORT") && [[ -n $real ]]; then host=${real,,}; fi
    [[ $host == ssh.github.com ]] && host=github.com
  fi
  hub::is_known_host "$host" || return 1
  HUB_URL_HOST=$host
}

# hub::remote_project NAME [push] : print owner/repo for a GitHub remote, from its fetch URL (with
# "push", from the URL it pushes to); also sets HUB_PROJECT and HUB_PROJECT_HOST. Returns 1 if the
# remote does not exist or does not point at a known GitHub host.
hub::remote_project() {
  local url
  if [[ ${2-} == push ]]; then
    url=$(hub::git_query remote get-url --push -- "$1") || return 1
  else
    url=$(hub::git_query remote get-url -- "$1") || return 1
  fi
  hub::parse_remote_url "$url" || return 1
  hub::canonical_host || return 1
  HUB_PROJECT_HOST=$HUB_URL_HOST
  HUB_PROJECT=$HUB_URL_OWNER/$HUB_URL_REPO
  printf '%s\n' "$HUB_PROJECT"
}

# hub::main_remote : the remote hub treats as "the" GitHub project: upstream, github, origin, then
# any other GitHub remote (among those `git remote` lists).
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

# hub::parse_project STR : OWNER/REPO, HOST/OWNER/REPO or a repository URL, gh's own rule for
# GH_REPO and -R: no empty or extra parts, no trailing slash on the shorthand forms. Sets
# HUB_PROJECT (owner/repo, without .git) and HUB_PROJECT_HOST (STR's host, else the default host).
hub::parse_project() {
  local s=$1 a b c
  HUB_PROJECT='' HUB_PROJECT_HOST=''
  if [[ $s == *://* || $s == git@* ]]; then
    hub::parse_remote_url "$s" || return 1
    HUB_PROJECT_HOST=$HUB_URL_HOST HUB_PROJECT=$HUB_URL_OWNER/$HUB_URL_REPO
    return 0
  fi
  [[ $s != */ && $s != /* && $s != *//* && $s != *[[:space:]]* ]] || return 1
  IFS=/ read -r a b c _ <<<"$s/"
  case $s in
    */*/*/*) return 1 ;;
    */*/*) HUB_PROJECT_HOST=$a HUB_PROJECT=$b/${c%.git} ;;
    */*) HUB_PROJECT=$a/${b%.git} ;;
    *) return 1 ;;
  esac
  [[ -n $HUB_PROJECT_HOST ]] || HUB_PROJECT_HOST=$(hub::host)
  [[ $HUB_PROJECT != */ && $HUB_PROJECT != /* ]]
}

# hub::main_project : owner/repo of the current project (GH_REPO overrides); also sets HUB_PROJECT and
# HUB_PROJECT_HOST. Dies if none.
hub::main_project() {
  if [[ -n ${GH_REPO:-} ]]; then
    hub::parse_project "$GH_REPO" || hub::die "Aborted: GH_REPO must be OWNER/REPO, HOST/OWNER/REPO or a repository URL, got: $GH_REPO"
    printf '%s\n' "$HUB_PROJECT"
    return 0
  fi
  local remote
  remote=$(hub::main_remote) || hub::die "Aborted: could not find a GitHub remote in this repository (looked for upstream, github, origin)"
  hub::remote_project "$remote"
}

# hub::project_or_dir : print "HOST REPO" for the current project, else the default host and the
# work tree's directory name (for commands that may run before a GitHub remote exists). A bare
# repository directory loses its .git suffix, as a URL would.
hub::project_or_dir() {
  local name
  if [[ -n ${GH_REPO:-} ]] || hub::main_remote >/dev/null; then
    hub::main_project >/dev/null
    printf '%s %s\n' "$HUB_PROJECT_HOST" "${HUB_PROJECT#*/}"
    return
  fi
  name=$(hub::toplevel) || name=$(hub::git_query rev-parse --absolute-git-dir) || name=$PWD
  name=${name%/}
  name=${name##*/}
  name=${name%.git}
  printf '%s %s\n' "$(hub::host)" "${name//[^A-Za-z0-9_.-]/-}"
}

# hub::remote_for_project OWNER/REPO HOST : print the name of a local remote pointing at that project.
hub::remote_for_project() {
  local remote
  while IFS= read -r remote; do
    hub::remote_project "$remote" >/dev/null || continue
    { [[ ${HUB_PROJECT,,} == "${1,,}" ]] && hub::same_host "$HUB_PROJECT_HOST" "$2"; } || continue
    printf '%s\n' "$remote"
    return 0
  done < <(hub::git_query remote)
  return 1
}

# hub::push_target BRANCH : where `git push` with no arguments would send BRANCH, by git's rules:
# remote.*.push refspecs, else push.default with branch.*.pushRemote, remote.pushDefault,
# branch.*.remote (origin when unset). Sets HUB_PUSH_REMOTE (the remote git would push to, when
# it exists, whatever the outcome) and HUB_PUSH_BRANCH (BRANCH's name on it). Returns 1 when git
# would not push BRANCH there, so that callers fail before pushing anywhere, with the reason in
# HUB_PUSH_WHY: remote (no such remote), refspec (remote.*.push is configured and none of its
# refspecs maps BRANCH, so `git push` would push other branches and leave this one alone),
# destination (a refspec maps it to something other than a branch), nothing (push.default),
# upstream (push.default simple or upstream without an upstream on that remote, or, for simple,
# one of another name) or matching (push.default matching, and the remote has no branch of that
# name: it pushes only branches both sides have). Whether the remote has the branch is read from
# its remote-tracking ref here, as of the last fetch, or, with VERIFY, asked of every URL git
# pushes the remote to (git ls-remote), as git asks at push time; a caller about to push verifies.
# The upstream is read as git push reads it, from branch.*.remote and branch.*.merge: %(upstream)
# has nothing to say when the remote's fetch refspecs map the upstream branch to no
# remote-tracking ref, and git pushes by the names all the same.
hub::push_target() {
  local branch=$1 verify=${2-} push_remote push_ref push_track up_remote up_ref mode
  HUB_PUSH_REMOTE='' HUB_PUSH_BRANCH='' HUB_PUSH_WHY=''
  IFS=$'\x1f' read -r push_remote push_ref push_track < <(hub::git_query for-each-ref \
    --format='%(push:remotename)%1f%(push:remoteref)%1f%(push)' -- "refs/heads/$branch")
  up_remote=$(hub::git_query config --get "branch.$branch.remote") || up_remote=''
  up_ref=$(hub::git_query config --get "branch.$branch.merge") || up_ref=''
  [[ -n $up_remote && -n $up_ref ]] || up_ref='' # an upstream is both settings, or none
  [[ -n $up_remote ]] || up_remote=origin
  [[ -n $push_remote ]] || push_remote=$up_remote
  hub::remote_exists "$push_remote" || {
    HUB_PUSH_WHY=remote
    return 1
  }
  HUB_PUSH_REMOTE=$push_remote
  if [[ -n $push_ref ]]; then # remote.NAME.push decides
    [[ $push_ref == refs/heads/?* ]] || {
      HUB_PUSH_WHY=destination
      return 1
    }
    HUB_PUSH_BRANCH=${push_ref#refs/heads/}
    return 0
  fi
  if hub::git_query config --get-all "remote.$push_remote.push" >/dev/null; then
    HUB_PUSH_WHY=refspec # configured, and none of them maps this branch
    return 1
  fi
  mode=$(hub::git_query config --get push.default) || mode=simple
  case $mode in
    nothing)
      HUB_PUSH_WHY=nothing
      return 1
      ;;
    current) HUB_PUSH_BRANCH=$branch ;;
    matching)
      HUB_PUSH_BRANCH=$branch
      if [[ -n $verify ]]; then
        hub::remote_has_branch "$push_remote" "$branch"
      else # %(push) is the remote-tracking ref of the branch's name on the remote
        [[ -n $push_track ]] && hub::git_query show-ref --verify --quiet -- "$push_track"
      fi || {
        HUB_PUSH_WHY=matching
        return 1
      }
      ;;
    upstream)
      [[ $up_remote == "$push_remote" && $up_ref == refs/heads/?* ]] || {
        HUB_PUSH_WHY=upstream
        return 1
      }
      HUB_PUSH_BRANCH=${up_ref#refs/heads/}
      ;;
    *) # simple: the same name, and when pushing to the upstream remote, an upstream of that name
      if [[ $up_remote == "$push_remote" && $up_ref != "refs/heads/$branch" ]]; then
        HUB_PUSH_WHY=upstream
        return 1
      fi
      HUB_PUSH_BRANCH=$branch
      ;;
  esac
}

# hub::remote_has_branch REMOTE BRANCH : every URL git pushes REMOTE to has a branch BRANCH right
# now (git ls-remote), as push.default matching requires to push it. Dies when a URL cannot be asked.
hub::remote_has_branch() {
  local url out
  while IFS= read -r url; do
    out=$(git ls-remote --heads --exit-code "$url" "refs/heads/$2" 2>&1) && continue
    (($? != 2)) || return 1 # no such branch
    hub::die "Aborted: could not list the branches of $url, to tell whether git push would push $2 (push.default matching):"$'\n'"$out"
  done < <(hub::git_query remote get-url --push --all "$1")
}

# hub::default_branch [REMOTE] : from refs/remotes/REMOTE/HEAD when it points at a branch that still
# exists, else from gh. Fails, printing nothing, when neither can tell: a command that only builds
# a URL may then assume main (`|| echo main`); one that changes something must not.
hub::default_branch() {
  local remote=${1:-} ref proj
  [[ -n $remote ]] || remote=$(hub::main_remote) || return 1
  if ref=$(hub::git_query symbolic-ref -q "refs/remotes/$remote/HEAD") && [[ $ref == "refs/remotes/$remote/"?* ]] \
    && hub::git_query show-ref --verify --quiet -- "$ref"; then
    printf '%s\n' "${ref#"refs/remotes/$remote/"}"
    return 0
  fi
  if hub::remote_project "$remote" >/dev/null; then
    proj=$HUB_PROJECT_HOST/$HUB_PROJECT # always with the host: gh's default host may differ
    if ref=$(hub::gh_query repo view "$proj" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null) && [[ -n $ref ]]; then
      printf '%s\n' "$ref"
      return 0
    fi
  fi
  return 1
}

# hub::tracking_ref REMOTE BRANCH : the remote-tracking ref that git fetch writes REMOTE's branch
# BRANCH to, as REMOTE's fetch refspecs (remote.REMOTE.fetch) map refs/heads/BRANCH: a negative
# refspec (^refs/heads/wip-*) that matches it keeps it from being fetched at all; else it goes to
# the destination of the first refspec whose source matches it, exactly or by its one *
# (+refs/heads/*:refs/remotes/REMOTE/* puts it at refs/remotes/REMOTE/BRANCH;
# +refs/heads/release:refs/remotes/REMOTE/next puts release at refs/remotes/REMOTE/next). A source
# git resolves against the remote at fetch time (release, without refs/heads/) matches nothing
# here, as it matches nothing for git's own %(upstream). Returns 1 when no refspec maps the branch,
# so that a ref of the conventional name is never read for it: under a custom mapping it holds
# another branch of the remote, or whatever else put it there.
hub::tracking_ref() {
  local src=refs/heads/$2 spec lhs rhs mid
  local -a specs
  mapfile -t specs < <(hub::git_query config --get-all "remote.$1.fetch")
  for spec in "${specs[@]}"; do
    [[ $spec == ^?* ]] && hub::ref_matches "${spec#^}" "$src" && return 1
  done
  for spec in "${specs[@]}"; do
    spec=${spec#+}
    [[ $spec != ^* && $spec == ?*:?* ]] || continue # without a destination, a refspec writes FETCH_HEAD alone
    lhs=${spec%%:*} rhs=${spec#*:}
    hub::ref_matches "$lhs" "$src" || continue
    if [[ $lhs == *'*'* ]]; then
      [[ $rhs == *'*'* ]] || return 1 # git refuses a * on one side alone
      mid=${src#"${lhs%%\**}"}
      mid=${mid%"${lhs#*\*}"}
      printf '%s\n' "${rhs%%\**}$mid${rhs#*\*}"
    else
      printf '%s\n' "$rhs"
    fi
    return 0
  done
  return 1
}

# hub::ref_matches PATTERN REF : REF is PATTERN, or matches it with its one * standing for any part
# of the name, the empty one included, as git matches the sides of a refspec.
hub::ref_matches() {
  if [[ $1 == *'*'* ]]; then
    [[ $2 == "${1%%\**}"*"${1#*\*}" ]]
  else
    [[ $2 == "$1" ]]
  fi
}

# hub::parse_github_url URL : sets HUB_URL_HOST, HUB_URL_OWNER, HUB_URL_REPO, HUB_URL_KIND, HUB_URL_NUMBER,
# HUB_URL_SHA, HUB_URL_PATH and HUB_URL_FORMAT for a GitHub web URL. KIND is repo | pull | issues | commit |
# gist | <first path segment, e.g. tree, blob, compare>. For pull URLs, HUB_URL_SHA is set when the URL
# points at one commit of the PR (.../pull/N/commits/SHA). FORMAT is patch or diff for the raw forms
# .../pull/N.patch, .../pull/N/commits/SHA.diff and .../commit/SHA.patch.
hub::parse_github_url() {
  local url=$1 host a b rest kind tail id
  HUB_URL_HOST='' HUB_URL_OWNER='' HUB_URL_REPO='' HUB_URL_KIND='' HUB_URL_NUMBER='' HUB_URL_SHA='' HUB_URL_PATH='' HUB_URL_FORMAT=''
  [[ $url =~ ^https?://([^/?#]+)/([^/?#]+)(/([^/?#]+)(/([^?#]*))?)?/?([?#].*)?$ ]] || return 1
  host=${BASH_REMATCH[1],,} a=${BASH_REMATCH[2]} b=${BASH_REMATCH[4]} rest=${BASH_REMATCH[6]}
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
      id=${tail%%/*}
      if [[ $tail == */commits/* ]]; then
        HUB_URL_SHA=${tail##*/commits/}
        HUB_URL_SHA=${HUB_URL_SHA%%/*}
        _hub_url_format HUB_URL_SHA
        [[ $HUB_URL_SHA =~ ^[0-9a-fA-F]{4,64}$ ]] || return 1 # only a hash is a commit, never a ref name
      elif [[ $tail != */* ]]; then
        _hub_url_format id
      fi
      HUB_URL_NUMBER=$id
      [[ $HUB_URL_NUMBER =~ ^[0-9]+$ ]] || return 1
      ;;
    commit)
      HUB_URL_SHA=${tail%%/*}
      [[ $tail != */* ]] && _hub_url_format HUB_URL_SHA
      [[ $HUB_URL_SHA =~ ^[0-9a-fA-F]{4,64}$ ]] || return 1
      ;;
    *) HUB_URL_PATH=$tail ;;
  esac
  return 0
}
# _hub_url_format VAR : strip a .patch or .diff suffix from VAR into HUB_URL_FORMAT.
_hub_url_format() {
  local -n v=$1
  case $v in
    *.patch | *.diff)
      HUB_URL_FORMAT=${v##*.}
      v=${v%.*}
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Identity, protocol, project shorthand
# ---------------------------------------------------------------------------
# hub::token_overrides HOST : true when an environment token takes precedence over gh's stored
# credentials for HOST, following gh's rule: GH_TOKEN/GITHUB_TOKEN for github.com and *.ghe.com,
# GH_ENTERPRISE_TOKEN/GITHUB_ENTERPRISE_TOKEN for every other host.
hub::token_overrides() {
  case ${1,,} in
    github.com | *.ghe.com) [[ -n ${GH_TOKEN:-}${GITHUB_TOKEN:-} ]] ;;
    *) [[ -n ${GH_ENTERPRISE_TOKEN:-}${GITHUB_ENTERPRISE_TOKEN:-} ]] ;;
  esac
}

# hub::current_user [HOST] : your login on HOST. Uses gh's cached login unless a token in the
# environment overrides gh's stored credentials (then only the API knows whose token it is). Dies if unknown.
hub::current_user() {
  local host=${1:-$(hub::host)} user
  if ! hub::token_overrides "$host"; then
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

# hub::git_url OWNER/REPO [HOST] [PROTOCOL] : clone URL for a project. On *.ghe.com hosts the SSH user is the
# tenant, as in gh, whether or not HOST carries a port. A HOST with a port keeps it for HTTPS; SSH URLs drop
# it (an HTTPS port says nothing about the SSH port).
hub::git_url() {
  local proj=$1 host=${2:-} proto=${3:-} user=git name
  [[ -n $host ]] || host=$(hub::host)
  [[ -n $proto ]] || proto=$(hub::protocol "$host")
  name=${host%%:*}
  case $proto in
    ssh | git)
      [[ ${name,,} == *.ghe.com ]] && user=${name%%.*}
      if [[ $host == *:* ]]; then
        # the port in GH_HOST is the HTTPS port; SSH uses its own, so leave it to ssh_config
        printf 'ssh://%s@%s/%s.git\n' "$user" "$name" "$proj"
      else
        printf '%s@%s:%s.git\n' "$user" "$host" "$proj"
      fi
      ;;
    *) printf 'https://%s/%s.git\n' "$host" "$proj" ;;
  esac
}

# hub::is_project_name STR : lexically a GitHub shorthand: "owner/repo" or "repo" (a repo name may
# start with a dot, as .github). Not . or .., and nothing with a path-like start. Whether git would
# read STR as something local is a separate question: hub::local_source, hub::remote_exists.
hub::is_project_name() {
  [[ $1 =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*/[A-Za-z0-9_.-]+$ || $1 =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]] || return 1
  [[ ${1##*/} != . && ${1##*/} != .. ]]
}

# hub::local_source STR [bundle] : git would read STR as a local repository: it exists as a path, or
# STR.git holds a repository (git's own suffix rule), or, with "bundle" (for clone), STR.bundle is a file.
hub::local_source() {
  [[ -e $1 ]] && return 0
  hub::git_query rev-parse --resolve-git-dir "$1.git" >/dev/null && return 0
  [[ ${2-} == bundle && -f $1.bundle ]]
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

# hub::message FILE [MESSAGE...] : HUB_MSG_TITLE and HUB_MSG_BODY from -m MESSAGEs (joined as
# paragraphs) or from FILE ("-" is standard input). Dies when both are given, FILE is unreadable or
# the read fails, before anything is sent anywhere.
hub::message() {
  local file=$1 text
  shift
  if [[ -n $file ]]; then
    (($# == 0)) || hub::die "Aborted: -m and -F cannot be used together."
    if [[ $file == - ]]; then
      text=$(cat) || hub::die "Aborted: could not read the message from standard input"
    else
      [[ -r $file && ! -d $file ]] || hub::die "Aborted: cannot read $file"
      text=$(cat -- "$file") || hub::die "Aborted: could not read $file"
    fi
  else
    text=$(printf '%s\n\n' "$@")
  fi
  hub::split_message "$text"
}

# hub::url_escape STR : percent-encode STR for a URL path; / : @ and unreserved characters stay.
hub::url_escape() {
  local LC_ALL=C s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~/:@-]) out+=$c ;;
      *)
        printf -v c '%%%02X' "'$c"
        out+=$c
        ;;
    esac
  done
  printf '%s\n' "$out"
}

# hub::url_segment STR : percent-encode STR as one path segment (or query value): everything but
# unreserved characters, / and # included, so that a ref name stays one API parameter.
hub::url_segment() {
  local LC_ALL=C s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      [A-Za-z0-9._~-]) out+=$c ;;
      *)
        printf -v c '%%%02X' "'$c"
        out+=$c
        ;;
    esac
  done
  printf '%s\n' "$out"
}

# hub::open_url URL : open in the browser (GH_BROWSER, BROWSER, else open/xdg-open). Printed under
# --noop. Returns the browser's status.
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
# Returns the clipboard tool's status.
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
