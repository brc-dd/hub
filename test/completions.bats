#!/usr/bin/env bats
# completions/: hub's commands and options in bash, zsh and fish, over stubbed git completions.
# The fish file is only syntax-checked, and only when fish is installed.

load test_helper

setup() {
  hub_test_setup
  export COMPLETION_STUBS=$HUB_TEST_TMP/stubs.bash COMPLETION_LOG=$HUB_TEST_TMP/completion.log
  # git's completion as far as hub's uses it: __git_main finds the command word after the
  # global options it knows take a value, as git's does, and offers four commands before one.
  cat >"$COMPLETION_STUBS" <<'EOF'
__git_func_wrap() {
  local cur words cword prev
  words=("${COMP_WORDS[@]}") cword=$COMP_CWORD
  cur=${words[cword]} prev=${words[cword - 1]}
  "$1"
}
__gitcomp() {
  local w
  for w in $1; do
    [[ $w == "$cur"* ]] || continue
    if [[ $w == *= ]]; then COMPREPLY+=("$w"); else COMPREPLY+=("$w "); fi
  done
}
__git_main() {
  local c=1 cmd=''
  echo "__git_main ${words[*]} ($cword)" >>"$COMPLETION_LOG"
  while ((c < cword)); do
    case ${words[c]} in
      -C | -c | --git-dir | --work-tree | --namespace) ((c++)) ;;
      -*) ;;
      *) cmd=${words[c]} && break ;;
    esac
    ((c++))
  done
  if [[ -z $cmd ]]; then
    case $prev in -C | -c | --git-dir | --work-tree | --namespace) return ;; esac
    __gitcomp 'add am pull status'
  elif declare -F "_git_${cmd//-/_}" >/dev/null; then
    "_git_${cmd//-/_}"
  fi
}
EOF
  # complete.bash SETUP AFTER [WORD...] : SETUP, hub.bash, AFTER, then the completion bash
  # runs for the command line WORD... (the last word is being completed), printing COMPREPLY
  # and any _git_ function the completion left behind.
  cat >"$HUB_TEST_TMP/complete.bash" <<'EOF'
eval "$1"
. "$HUB_TEST_ROOT/completions/hub.bash" || exit
eval "$2"
shift 2
(($#)) || exit 0
before=$(compgen -A function _git_)
COMP_WORDS=("$@") COMP_CWORD=$(($# - 1)) COMPREPLY=()
read -r -a spec <<<"$(complete -p "$1")"
for ((i = 0; i + 1 < ${#spec[@]}; i++)); do
  [[ ${spec[i]} != -F ]] || fn=${spec[i + 1]}
done
"$fn" "$1" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD - 1]}"
((${#COMPREPLY[@]} == 0)) || printf '%s\n' "${COMPREPLY[@]}"
comm -13 <(echo "$before") <(compgen -A function _git_) | sed 's/^/leftover /'
EOF
  # complete.zsh SETUP [WORD...] : the same for zsh, over a _git that prints what it was given
  # and runs the _git-CMD function for a command word just before the word being completed.
  # Like zsh's, it defines its own _git-version on its first run unless one exists.
  cat >"$HUB_TEST_TMP/complete.zsh" <<'EOF'
compdef() { print -r -- "compdef $*"; }
_git() {
  (( $+functions[_git-version] )) || _git-version() { print -r -- "git's _git-version"; }
  print -r -- "_git $service $CURRENT ${words[*]}"
  local cmd=$words[CURRENT-1]
  if (( $+functions[_git-$cmd] )); then
    words=($cmd $PREFIX) CURRENT=2
    _git-$cmd
  fi
}
_describe() { print -r -- "_describe $3: ${(@P)4%%:*}"; }
_default() { print -r -- _default; }
eval "$1"
source $HUB_TEST_ROOT/completions/hub.zsh
shift
if (( $# )); then
  words=("$@") CURRENT=$# PREFIX=$argv[-1]
  _hub
  print -r -- "after: $CURRENT ${words[*]}"
fi
left=(${${(k)functions[(I)_git-*]}:#_git-version})
(( ! $#left )) || print -l -- ${left/#/leftover }
EOF
}

# complete_bash [-b BASH] SETUP AFTER [WORD...] : runs complete.bash (with BASH).
complete_bash() {
  local bash=bash
  if [[ $1 == -b ]]; then bash=$2 && shift 2; fi
  run "$bash" --noprofile --norc "$HUB_TEST_TMP/complete.bash" "$@"
}

# complete_hub [-b BASH] WORD... : the bash completion of WORD... over the stubs.
complete_hub() {
  local -a bash=()
  if [[ $1 == -b ]]; then bash=(-b "$2") && shift 2; fi
  complete_bash "${bash[@]}" '. "$COMPLETION_STUBS"' '' "$@"
}

complete_zsh() { run zsh -f "$HUB_TEST_TMP/complete.zsh" "$@"; }
# has_zsh : zsh is on PATH.
has_zsh() { command -v zsh >/dev/null; }
# need_zsh : skip the test unless zsh is on PATH.
need_zsh() { has_zsh || skip 'zsh is not installed'; }

modules() {
  local f
  for f in "$HUB_TEST_ROOT"/lib/hub/cmd/*.sh; do
    f=${f##*/} && echo "${f%.sh}"
  done
}

# with_space WORD... : the words one per line, sorted, each with a trailing space.
with_space() { printf '%s \n' "$@" | sort -u; }
# offered : what hub '' offers: the stubbed git's commands and hub's.
offered() { { printf '%s\n' add am pull status && modules; } | sed 's/$/ /' | sort -u; }
# git_modules : the modules that are git commands too.
git_modules() { modules | grep -Fx -f <(git --list-cmds=main); }
# hub_only : the other modules, on one line.
hub_only() { modules | grep -vFx -f <(git --list-cmds=main) | tr '\n' ' ' | sed 's/ $//'; }
sorted_output() { printf '%s\n' "${lines[@]}" | sort; }

# summary MODULE : the module's summary without its period.
summary() {
  local line
  line=$(grep -m 1 '^# Summary: ' "$HUB_TEST_ROOT/lib/hub/cmd/$1.sh")
  line=${line#'# Summary: '} && echo "${line%.}"
}

# header_options MODULE : SHORT LONG VALUED for each option of the header, - for none.
header_options() {
  local line in_options=0
  local re='^#\ +(-[A-Za-z0-9])?(, )?(--[a-z][a-z-]*)?( [A-Z]+)?( |$)'
  while IFS= read -r line && [[ $line == '#'* ]]; do
    [[ $line != '# Options:' ]] || in_options=1
    ((in_options)) && [[ $line =~ $re ]] || continue
    [[ -n ${BASH_REMATCH[1]}${BASH_REMATCH[3]} ]] || continue
    echo "${BASH_REMATCH[1]:--} ${BASH_REMATCH[3]:--} $((${#BASH_REMATCH[4]} > 0))"
  done <"$HUB_TEST_ROOT/lib/hub/cmd/$1.sh"
}

own_command() { grep -q "^# hub's own command" "$HUB_TEST_ROOT/lib/hub/cmd/$1.sh"; }

# fish_lines : hub.fish with its continuation lines joined.
fish_lines() {
  sed -e ':a' -e '/\\$/{N;s/\\\n *//;ba' -e '}' "$HUB_TEST_ROOT/completions/hub.fish"
}

@test "bash: hub's commands at the command position, with git's, each once" {
  complete_hub hub ''
  assert_success
  assert_equals "$(sorted_output)" "$(offered)"
  complete_hub hub pu
  assert_equals "$(sorted_output)" "$(with_space pull pull-request push)"
}

@test "bash: hub's commands after global options, without the pairs git cannot skip" {
  complete_hub hub --noop -C dir --attr-source HEAD --config-env a=B -c x=y --bare pull-
  assert_success
  assert_output_equals 'pull-request '
  assert_equals "$(<"$COMPLETION_LOG")" '__git_main hub --noop -C dir -c x=y --bare pull- (7)'
}

@test "bash: no hub command for a global option's value or after git's own options" {
  local words
  for words in '-C' '-c' '--git-dir' '--attr-source' '--super-prefix' '--version' '--help'; do
    complete_hub hub "$words" ''
    assert_success
    assert_output_lacks 'pull-request'
  done
}

@test "bash: the options of hub's own commands, defined for one completion only" {
  complete_hub hub -C dir pull-request --ba
  assert_success
  assert_output_equals '--base='
  complete_hub hub browse --
  assert_equals "$(sorted_output)" "$(with_space --copy --url)"
  complete_hub hub alias -
  assert_output_equals '-s '
  complete_hub hub gist --
  assert_output_equals ''
  complete_hub hub sync --
  assert_output_equals ''
}

@test "bash: a _git_CMD function of yours completes hub's command" {
  complete_bash '. "$COMPLETION_STUBS"; _git_browse() { COMPREPLY=(mine); }' '' hub browse --
  assert_success
  assert_output_equals 'mine'
}

@test "bash: plain git keeps git's completion, git aliased to hub gets hub's commands" {
  complete_bash '. "$COMPLETION_STUBS"' 'complete -p git' git ''
  assert_success
  assert_line_equals 0 'complete -o bashdefault -o default -o nospace -F __hub_wrap git'
  assert_equals "$(printf '%s\n' "${lines[@]:1}")" "$(with_space add am pull status)"
  complete_bash '. "$COMPLETION_STUBS"; alias git=hub' '' git pull-
  assert_output_equals 'pull-request '
  complete_bash ". \"\$COMPLETION_STUBS\"; alias git='/opt/hub/bin/hub --noop'" '' git pull-
  assert_output_equals 'pull-request '
}

@test "bash: a complete -F registration of yours for git keeps completing plain git" {
  local mine='. "$COMPLETION_STUBS"; mine() { COMPREPLY=("mine $1/$2/$3"); }'
  mine+='; complete -o default -F mine git'
  complete_bash "$mine" 'complete -p git' git st
  assert_success
  assert_output_equals $'complete -o default -F __hub_wrap git\nmine git/st/git'
  complete_bash "$mine; alias git=hub" '' git pull-
  assert_output_equals 'pull-request '
}

@test "bash: sourcing the file twice changes nothing" {
  local mine='. "$COMPLETION_STUBS"; mine() { COMPREPLY=("mine $1/$2/$3"); }'
  mine+='; complete -F mine git; . "$HUB_TEST_ROOT/completions/hub.bash"'
  complete_bash "$mine" 'complete -p git hub' git ''
  assert_success
  assert_line_equals 0 'complete -F __hub_wrap git'
  assert_line_equals 1 'complete -o bashdefault -o default -o nospace -F __hub_wrap hub'
  assert_line_equals 2 'mine git//git'
  assert_equals "${#lines[@]}" 3
}

@test "bash: a git registration that is not a function is left alone" {
  complete_bash '. "$COMPLETION_STUBS"; complete -W "x y" git' 'complete -p git' git ''
  assert_success
  assert_line_equals 0 "complete -W 'x y' git"
}

@test "bash: git's completion is loaded through _comp_load or _completion_loader" {
  local loader
  for loader in _comp_load _completion_loader; do
    : >"$COMPLETION_LOG"
    complete_bash "$loader() { echo \"$loader \$*\" >>\"\$COMPLETION_LOG\"
      . \"\$COMPLETION_STUBS\"; }" '' hub pull-
    assert_success
    assert_output_equals 'pull-request '
    assert_equals "$(head -n 1 "$COMPLETION_LOG")" "$loader git"
  done
}

@test "bash: the file runs on macOS's bash 3.2" {
  [[ -x /bin/bash ]] && /bin/bash -c '((BASH_VERSINFO[0] < 5))' \
    || skip '/bin/bash is not older than bash 5'
  complete_hub -b /bin/bash hub -C dir --attr-source HEAD ''
  assert_success
  assert_equals "$(sorted_output)" "$(offered)"
  complete_hub -b /bin/bash hub pull-request --ba
  assert_output_equals '--base='
  complete_bash -b /bin/bash \
    '. "$COMPLETION_STUBS"; mine() { COMPREPLY=(mine); }; complete -F mine git' '' git ''
  assert_output_equals 'mine'
}

@test "bash: with git's own completion file" {
  local file share
  share=$(env -u GIT_EXEC_PATH git --exec-path) && share=${share%/libexec/git-core}/share
  for file in /usr/share/bash-completion/completions/git \
    /opt/homebrew/etc/bash_completion.d/git-completion.bash \
    "$share/git-core/git-completion.bash" \
    "$share/git-core/contrib/completion/git-completion.bash"; do
    [[ ! -r $file ]] || break
    file=''
  done
  [[ -n $file ]] || skip "git's bash completion is not installed"
  export GIT_COMPLETION=$file
  complete_bash '. "$GIT_COMPLETION"' '' hub pul
  assert_success
  assert_equals "$(sorted_output)" "$(with_space pull pull-request)"
  complete_bash '. "$GIT_COMPLETION"' '' hub -C . pull-request --dr
  assert_output_equals '--draft '
  complete_bash '. "$GIT_COMPLETION"' 'complete -p git' git ch
  assert_line_equals 0 'complete -o bashdefault -o default -o nospace -F __hub_wrap git'
  assert_output_contains 'checkout '
  assert_output_lacks 'ci-status'
}

@test "bash: a -F inside another option's value is not git's function" {
  local mine='. "$COMPLETION_STUBS"; mine() { COMPREPLY=(mine); }'
  mine+="; complete -o default -X '!*.txt -F x' -F mine git"
  complete_bash "$mine" 'complete -p git' git ''
  assert_success
  assert_output_equals $'complete -o default -X \'!*.txt -F x\' -F __hub_wrap git\nmine'
  complete_bash ". \"\$COMPLETION_STUBS\"; complete -o default -X '!*.txt -F x' git" \
    'complete -p git'
  assert_success
  assert_output_equals "complete -o default -X '!*.txt -F x' git"
}

@test "bash: without git's completion, hub's command names only" {
  complete_bash '__git_main() { :; }' 'complete -p hub' hub pu
  assert_success
  assert_line_equals 0 'complete -o default -F __hub_fallback hub'
  assert_equals "$(printf '%s\n' "${lines[@]:1}")" $'pull-request\npush'
  complete_bash '__git_main() { :; }' '' hub pull-request ''
  assert_output_equals ''
}

@test "zsh: registers _hub for hub and git, sourced or found by compinit" {
  need_zsh
  complete_zsh ''
  assert_success
  assert_output_equals 'compdef _hub hub git'
  mkdir fn && cp "$HUB_TEST_ROOT/completions/hub.zsh" fn/_hub
  run zsh -f -c 'fpath=("$1" $fpath); autoload -Uz compinit; compinit -u -D
    print -r -- $_comps[hub] $_comps[git]' zsh "$HUB_TEST_TMP/fn"
  assert_success
  assert_output_equals '_hub _hub'
}

@test "zsh: wraps the completer git had, never itself, when sourced twice" {
  need_zsh
  run zsh -f -c 'compdef() { local n; for n in ${@:2}; do _comps[$n]=$1; done; }
    typeset -A _comps; _comps[git]=_my_git
    source "$1"; source "$1"; print -r -- $_hub_git $_comps[git]' \
    zsh "$HUB_TEST_ROOT/completions/hub.zsh"
  assert_success
  assert_output_equals '_my_git _hub'
  run zsh -f -c 'typeset -A _comps; _comps[git]=_hub; source "$1"; print -r -- $_hub_git' \
    zsh "$HUB_TEST_ROOT/completions/hub.zsh"
  assert_output_equals '_git'
}

@test "zsh: hub's commands after global options, without the words _git cannot skip" {
  need_zsh
  complete_zsh '' hub --noop -C dir --attr-source HEAD -c x=y pull-
  assert_success
  assert_line_equals 1 '_git git 6 hub -C dir -c x=y pull-'
  assert_line_equals 2 "_describe hub command: $(hub_only)"
  assert_line_equals 3 'after: 9 hub --noop -C dir --attr-source HEAD -c x=y pull-'
  assert_equals "${#lines[@]}" 4
}

@test "zsh: no hub command for a global option's value, after a command or for plain git" {
  need_zsh
  complete_zsh '' hub -C ''
  assert_success
  assert_output_lacks '_describe'
  complete_zsh '' hub status ''
  assert_output_lacks '_describe'
  complete_zsh '' git ''
  assert_line_equals 1 '_git git 2 git '
  assert_output_lacks '_describe'
  complete_zsh 'alias git=hub' git ''
  assert_output_contains '_describe hub command: alias api'
}

@test "zsh: the commands git has too are left to git, with git's _git-CMD" {
  need_zsh
  assert_equals "$(zsh -f -c 'source "$1"; print -l -- $_hub_git_commands' zsh \
    "$HUB_TEST_ROOT/completions/hub.zsh")" "$(git_modules)"
  complete_zsh 'zshexit() { print -r -- "kept: $+functions[_git-version]"; }' hub version -
  assert_success
  assert_line_equals 2 "git's _git-version"
  assert_line_equals -1 'kept: 1'
}

@test "zsh: the options of hub's own commands, defined for one completion only" {
  need_zsh
  complete_zsh '' hub browse -
  assert_success
  assert_line_equals 2 '_describe option: -u --url -c --copy'
  assert_output_lacks 'leftover'
  complete_zsh '' hub browse ''
  assert_line_equals 2 '_default'
  complete_zsh '_git-browse() { print mine; }' hub browse -
  assert_line_equals 2 'mine'
  complete_zsh '' hub gist -
  assert_output_lacks '_describe option'
}

@test "zsh: the file autoloaded as _hub completes the first call" {
  need_zsh
  mkdir fn && cp "$HUB_TEST_ROOT/completions/hub.zsh" fn/_hub
  run zsh -f -c 'compdef() { :; }; _git() { print -r -- "_git $words"; }
    _describe() { print -r -- "_describe $3"; }
    fpath=("$1" $fpath); autoload -Uz _hub; words=(hub ""); CURRENT=2; _hub' \
    zsh "$HUB_TEST_TMP/fn"
  assert_success
  assert_output_equals $'_git hub \n_describe hub command'
}

@test "fish: the file parses" {
  command -v fish >/dev/null || skip 'fish is not installed'
  run fish -n "$HUB_TEST_ROOT/completions/hub.fish"
  assert_success
}

@test "every file lists the commands of lib/hub/cmd, with their summaries" {
  local -a expected=() names=() bash_names
  local module line re
  for module in $(modules); do
    expected+=("$module:$(summary "$module")")
  done
  run bash --noprofile --norc -c '__git_main() { :; }; __git_func_wrap() { :; }
    . "$1"; printf "%s\n" $__hub_commands' bash "$HUB_TEST_ROOT/completions/hub.bash"
  assert_success
  bash_names=("${lines[@]}")
  assert_equals "${bash_names[*]}" "$(modules | tr '\n' ' ' | sed 's/ $//')"
  if has_zsh; then
    run zsh -f -c 'source "$1"; print -l -- $_hub_commands' zsh \
      "$HUB_TEST_ROOT/completions/hub.zsh"
    assert_success
    assert_equals "$(printf '%s\n' "${lines[@]}")" "$(printf '%s\n' "${expected[@]}")"
  fi
  re="^complete -c hub -n __hub_needs_command -a ([a-z-]+) -d ['\"](.*)['\"]$"
  while IFS= read -r line; do
    [[ $line =~ $re ]] && names+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]}")
  done < <(fish_lines)
  assert_equals "$(printf '%s\n' "${names[@]}")" "$(printf '%s\n' "${expected[@]}")"
}

@test "every file offers the options of hub's own commands' headers, and no others" {
  local module short long valued expected_bash expected_zsh expected_fish fish line
  local re="^complete -c hub -n '__hub_using ([a-z-]+)'( -s ([A-Za-z]))?( -l ([a-z-]+))?( -r)? -d"
  for module in $(modules); do
    expected_bash='' expected_zsh='' expected_fish=''
    if own_command "$module"; then
      while read -r short long valued; do
        if [[ $long == - ]]; then expected_bash+=" $short"; else expected_bash+=" $long"; fi
        ((valued)) && [[ $long != - ]] && expected_bash+='='
        [[ $short == - ]] || expected_zsh+=" $short"
        [[ $long == - ]] || expected_zsh+=" $long"
        [[ $short == - ]] || short=${short#-}
        [[ $long == - ]] || long=${long#--}
        expected_fish+=" $short/$long/$valued"
      done < <(header_options "$module")
    fi
    git_modules | grep -qx -- "$module" && expected_zsh=''
    run bash --noprofile --norc -c '__git_main() { :; }; __git_func_wrap() { :; }
      . "$1"; __hub_options "$2"' bash "$HUB_TEST_ROOT/completions/hub.bash" "$module"
    assert_equals "$module:$(echo $output)" "$module:$(echo $expected_bash)"
    if has_zsh; then
      run zsh -f -c 'source "$1"; _hub_options "$2" && print -r -- ${reply%%:*}' \
        zsh "$HUB_TEST_ROOT/completions/hub.zsh" "$module"
      assert_equals "$module:$output" "$module:$(echo $expected_zsh)"
    fi
    fish=''
    while IFS= read -r line; do
      [[ $line =~ $re && ${BASH_REMATCH[1]} == "$module" ]] || continue
      fish+=" ${BASH_REMATCH[3]:--}/${BASH_REMATCH[5]:--}/$((${#BASH_REMATCH[6]} > 0))"
    done < <(fish_lines)
    assert_equals "$module:$(echo $fish)" "$module:$(echo $expected_fish)"
  done
}
