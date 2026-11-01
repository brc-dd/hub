#!/usr/bin/env bats
# hub alias: the alias line for each shell and the startup file it goes in.

load test_helper

@test "hub alias -s prints the alias for every shell" {
  local shell
  for shell in bash zsh sh ksh dash fish; do
    run hub alias -s "$shell"
    assert_success
    assert_output_equals 'alias git=hub'
  done
  for shell in csh tcsh; do
    run hub alias -s "$shell"
    assert_success
    assert_output_equals 'alias git hub'
  done
}

@test "hub alias names each shell's startup file and the line for it" {
  local shell rc
  local head='# Add this line to'
  local tail='after the lines that set up PATH:'
  for shell in 'bash:~/.bashrc' 'zsh:~/.zshrc' 'ksh:~/.kshrc' 'sh:~/.profile' 'dash:~/.profile'; do
    rc=${shell#*:} shell=${shell%%:*}
    run hub alias "$shell"
    assert_success
    assert_output_equals "$head $rc, $tail"$'\n'"eval \"\$(hub alias -s $shell)\""
  done
  for shell in csh tcsh; do
    run hub alias "$shell"
    assert_output_equals "$head ~/.${shell}rc, $tail"$'\n'"eval \"\`hub alias -s $shell\`\""
  done
  run hub alias fish
  assert_output_equals "$head ~/.config/fish/config.fish, $tail"$'\nhub alias -s fish | source'
}

@test "hub alias takes the shell from SHELL, and -s anywhere" {
  SHELL=/usr/local/bin/tcsh run hub alias
  assert_success
  assert_line_equals 1 'eval "`hub alias -s tcsh`"'
  SHELL=/bin/zsh run hub alias -s
  assert_output_equals 'alias git=hub'
  run hub alias csh -s
  assert_output_equals 'alias git hub'
  run hub alias -- fish
  assert_line_equals 1 'hub alias -s fish | source'
}

@test "hub alias refuses an empty SHELL, an unsupported shell and extra words" {
  SHELL='' run hub alias
  assert_status 1
  assert_output_equals 'hub alias: cannot tell your shell from SHELL (name it: hub alias SHELL)'
  run hub alias /bin/zsh
  assert_status 1
  local shells='bash, zsh, sh, ksh, dash, fish, csh, tcsh'
  assert_output_equals "hub alias: unsupported shell: /bin/zsh (use one of $shells)"
  run hub alias bash zsh
  assert_status 1
  assert_line_equals 0 'hub alias: unexpected argument: zsh'
  assert_line_equals 1 'Usage: hub alias [-s] [SHELL]'
  run hub alias -x bash
  assert_status 1
  assert_line_equals 0 'hub alias: unknown option: -x'
  run hub alias -sx bash
  assert_line_equals 0 'hub alias: unknown option: -x'
}

@test "hub alias --help prints its manual" {
  run hub alias --help
  assert_success
  assert_line_equals 0 'Summary: Show how to make git run hub.'
  assert_line_equals 1 'Usage: hub alias [-s] [SHELL]'
}
