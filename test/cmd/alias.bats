#!/usr/bin/env bats
load ../test_helper

@test "alias -s prints alias git=hub for POSIX-style shells and fish" {
  local sh
  for sh in bash zsh sh ksh dash fish; do
    run hub alias -s "$sh"
    assert_success
    assert_output_equals "alias git=hub"
  done
}

@test "alias -s prints csh syntax for csh and tcsh" {
  run hub alias -s csh
  assert_success
  assert_output_equals "alias git hub"
  run hub alias -s tcsh
  assert_output_equals "alias git hub"
}

@test "alias defaults to the shell in SHELL" {
  SHELL=/bin/zsh run hub alias -s
  assert_success
  assert_output_equals "alias git=hub"
  SHELL=/bin/tcsh run hub alias -s
  assert_output_equals "alias git hub"
  SHELL=/opt/homebrew/bin/zsh run hub alias
  assert_output_equals $'# Make git run hub: add this line to ~/.zshrc, after the lines that set up PATH\neval "$(hub alias -s zsh)"'
  SHELL=/bin/zsh run hub alias fish # a named shell wins
  assert_output_equals $'# Make git run hub: add this line to ~/.config/fish/config.fish, after the lines that set up PATH\nhub alias -s fish | source'
}

@test "alias without -s says where to put the line" {
  run hub alias bash
  assert_success
  assert_output_equals $'# Make git run hub: add this line to ~/.bashrc, after the lines that set up PATH\neval "$(hub alias -s bash)"'
  run hub alias zsh
  assert_output_equals $'# Make git run hub: add this line to ~/.zshrc, after the lines that set up PATH\neval "$(hub alias -s zsh)"'
  run hub alias tcsh
  assert_output_equals $'# Make git run hub: add this line to ~/.tcshrc, after the lines that set up PATH\neval "`hub alias -s tcsh`"'
  run hub alias fish
  assert_output_equals $'# Make git run hub: add this line to ~/.config/fish/config.fish, after the lines that set up PATH\nhub alias -s fish | source'
  run hub alias ksh
  assert_line_equals 0 "# Make git run hub: add this line to ~/.kshrc, after the lines that set up PATH"
  run hub alias sh
  assert_line_equals 0 "# Make git run hub: add this line to ~/.profile, after the lines that set up PATH"
}

@test "alias rejects shells it does not know" {
  run hub alias -s rc
  assert_failure
  assert_output_equals "hub alias: unsupported shell: rc (supported: bash, zsh, sh, ksh, dash, fish, csh, tcsh)"
  run hub alias nushell
  assert_failure
  assert_output_contains "hub alias: unsupported shell: nushell"
  SHELL='' run hub alias -s
  assert_failure
  assert_output_contains "can't tell your shell"
}

@test "alias rejects unknown options and more than one shell" {
  run hub alias --script zsh
  assert_failure
  assert_output_equals $'hub alias: unknown option: --script\nUsage: hub alias [-s] [SHELL]'
  run hub alias -x
  assert_failure
  assert_output_contains "hub alias: unknown option: -x"
  run hub alias -s bash zsh
  assert_failure
  assert_output_contains "hub alias: name one shell"
  run hub alias -s -- zsh
  assert_success
  assert_output_equals "alias git=hub"
}

@test "alias does not need a repository or gh" {
  run hub --noop alias -s zsh
  assert_success
  assert_output_equals "alias git=hub"
  assert_gh_not_called
}

@test "the printed snippets define the alias in real shells" {
  local sh snippet out
  for sh in bash zsh dash ksh; do
    command -v "$sh" >/dev/null || continue
    snippet=$("$HUB_BIN" alias -s "$sh")
    out=$("$sh" -c "$snippet; alias git")
    [[ $out == *git* && $out == *hub* ]] || {
      echo "$sh: $out"
      return 1
    }
  done
  for sh in csh tcsh; do
    command -v "$sh" >/dev/null || continue
    snippet=$("$HUB_BIN" alias -s "$sh")
    out=$("$sh" -fc "eval \"$snippet\"; alias git")
    [[ $out == hub ]] || {
      echo "$sh: $out"
      return 1
    }
  done
  command -v fish >/dev/null || return 0
  out=$(fish -c "$HUB_BIN alias -s fish | source; alias")
  [[ $out == *"alias git hub"* ]] || {
    echo "fish: $out"
    return 1
  }
}

@test "alias --help explains why aliasing git is safe" {
  run hub alias --help
  assert_success
  assert_output_contains "runs the real git, untouched, for everything"
  assert_output_contains "Usage: hub alias [-s] [SHELL]"
}
