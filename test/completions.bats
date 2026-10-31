#!/usr/bin/env bats
load test_helper

# The bash completion, sourced into a bash of its own with the pieces of git's completion it
# uses stubbed: __git_main records that it ran, with the words it saw.
setup() {
  hub_test_setup
  cat >"$HUB_TEST_TMP/stubs.bash" <<'EOF'
__git_main() { COMPREPLY+=("git-main:${words[*]}:$cword"); }
__git_func_wrap() {
  local cur words cword prev
  local __git_cmd_idx=0
  words=("${COMP_WORDS[@]}") cword=$COMP_CWORD cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD - 1]}
  $1
}
__gitcomp() { COMPREPLY+=($1); }
__gitcomp_nl() { COMPREPLY+=($1); }
__git_find_on_cmdline() { :; }
# complete_for NAME WORD... : what bash offers for the command line WORD... (the last word is the
# one being completed) through the function registered for NAME, one per line
complete_for() {
  local spec fn
  spec=$(complete -p "$1") || return 1
  fn=${spec##* -F } fn=${fn%% *}
  COMP_WORDS=("${@:2}") COMP_CWORD=$(($# - 2)) COMP_LINE="${*:2}" COMP_POINT=${#COMP_LINE} COMPREPLY=()
  "$fn" "$1" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD - 1]}"
  printf '%s\n' "${COMPREPLY[@]}"
}
EOF
}

# in_bash SCRIPT : SCRIPT in a bash with the stubs loaded; hub.bash is the completion file.
in_bash() {
  bash --noprofile --norc -c ". '$HUB_TEST_TMP/stubs.bash'; hub_bash='$HUB_TEST_ROOT/completions/hub.bash'; $1"
}

@test "without a completion for git, the bash completion registers git's own for it, plus hub's commands through the alias" {
  run in_bash '. "$hub_bash"; complete -p git; complete -p hub; complete_for git git che; complete_for hub hub pu; alias git=hub; complete_for git git pu'
  assert_success
  assert_line_equals 0 "complete -o bashdefault -o default -o nospace -F __hub_wrap git"
  assert_line_equals 1 "complete -o bashdefault -o default -o nospace -F __hub_wrap hub"
  assert_line_equals 2 "git-main:git che:1" # plain git: git's completion, nothing of hub's
  assert_line_equals 3 "git-main:hub pu:1"  # hub: git's completion and hub's commands
  assert_line_equals 4 "pull-request "
  assert_line_equals 5 "git-main:git pu:1" # the alias: the same
  assert_line_equals 6 "pull-request "
}

@test "a completion the user registered for git keeps completing plain git, with its options" {
  run in_bash '_my_git() { COMPREPLY=("mine:$1:$2:$3:${COMP_WORDS[*]}"); }
    complete -o default -o filenames -F _my_git git
    . "$hub_bash"; complete -p git; complete_for git git che; alias git=hub; complete_for git git pu'
  assert_success
  assert_line_equals 0 "complete -o default -o filenames -F __hub_wrap git" # the options it had, hub in front of its function
  assert_line_equals 1 "mine:git:che:git:git che"                           # plain git: the user's function, with its arguments
  assert_line_equals 2 "git-main:git pu:1"                                  # through the alias: git's completion and hub's commands
  assert_line_equals 3 "pull-request "
  # git's own registration (__git_complete git __git_main) is kept the same way
  run in_bash '__git_wrap__git_main() { __git_func_wrap __git_main; }
    complete -o bashdefault -o default -o nospace -F __git_wrap__git_main git
    . "$hub_bash"; complete -p git; complete_for git git che'
  assert_success
  assert_line_equals 0 "complete -o bashdefault -o default -o nospace -F __hub_wrap git"
  assert_line_equals 1 "git-main:git che:1"
}

@test "a registration for git that is not a function is left as it is" {
  run in_bash 'complete -C "echo x" git; . "$hub_bash"; complete -p git; complete -p hub'
  assert_success
  assert_line_equals 0 "complete -C 'echo x' git"
  assert_line_equals 1 "complete -o bashdefault -o default -o nospace -F __hub_wrap hub"
}

@test "sourcing the bash completion again keeps what git had before it" {
  run in_bash '_my_git() { COMPREPLY=("mine:$1:$2:$3"); }
    complete -F _my_git git
    . "$hub_bash"; . "$hub_bash"; complete -p git; complete_for git git che'
  assert_success
  assert_line_equals 0 "complete -F __hub_wrap git"
  assert_line_equals 1 "mine:git:che:git"
}
