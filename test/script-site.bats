#!/usr/bin/env bats
# script/site: hub's manuals as a static website, built from the checkout and from a fixture copy.

load test_helper

site() { "$HUB_TEST_ROOT/script/site" "$@"; }

# squeeze : stdin with every run of white space as one space, none at either end.
squeeze() { tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }

# main_text PAGE : the text of PAGE's <main>, tags stripped and entities decoded, squeezed.
main_text() {
  sed -n '/^<main>$/,/^<\/main>$/p' "$1" \
    | sed 's/<[^>]*>//g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g' | squeeze
}

# manual_text TITLE : TITLE and the manual on stdin as a page shows it (no "Summary: ", no
# shebang, no colon after a heading), squeezed.
manual_text() {
  {
    printf '%s\n' "$1"
    awk 'NR == 1 && /^!/ { next } { line[++n] = $0 }
      END {
        sub(/^Summary: /, "", line[1])
        for (i = 1; i <= n; i++) {
          if (line[i] ~ /^[^ ].*:$/ && line[i + 1] ~ /^  /) sub(/:$/, "", line[i])
          print line[i]
        }
      }'
  } | squeeze
}

# module_doc FILE : hub::module_doc's sed.
module_doc() { sed -n '/^#/!q; /^# shellcheck /d; s/^#//; s/^ //; p' "$1"; }

# make_fixture : a copy of the checkout's sources in fixture/, with a module zz of its own.
make_fixture() {
  mkdir fixture
  cp -R "$HUB_TEST_ROOT"/{bin,lib,script,VERSION,Formula} fixture/
  cat >fixture/lib/hub/cmd/zz.sh <<'SH'
# shellcheck shell=bash
# Summary: A & B <C>
# Usage: hub zz [-x] ARG
#        hub zz --long
#
# The first line of a paragraph
# that spans three lines
# and ends *here* _now_ [a] | b.
#
# Second paragraph.
#
# Options:
#   -x   The x option.
#     --deep   A deeper line.
#
#   $ hub zz a
#   > cmd && other

hub_cmd_zz() { :; }
SH
}

@test "site writes the index and one page per module, and nothing else" {
  local expected=index.html file name
  for file in "$HUB_TEST_ROOT"/lib/hub/cmd/*.sh; do
    name=${file##*/}
    expected+=$'\n'${name%.sh}.html
  done
  run site out
  assert_success
  assert_output_equals ''
  assert_equals "$(ls -A out | LC_ALL=C sort)" "$(LC_ALL=C sort <<<"$expected")"
}

@test "site lists every command in the index with its Summary and a working link" {
  local file name summary href
  site out
  for file in "$HUB_TEST_ROOT"/lib/hub/cmd/*.sh; do
    name=${file##*/}
    name=${name%.sh}
    summary=$(module_doc "$file" | sed -n '1s/^Summary: //p')
    summary=${summary//&/'&amp;'}
    summary=${summary//</'&lt;'}
    summary=${summary//>/'&gt;'}
    run grep -cxF "<dt><a href=\"$name.html\">hub $name</a></dt><dd>$summary</dd>" out/index.html
    assert_output_equals 1
  done
  for href in $(sed -n 's/^<dt><a href="\([^"]*\)".*/\1/p' out/index.html); do
    [[ -f out/$href ]] || {
      echo "index links to a missing page: $href"
      return 1
    }
  done
}

@test "site gives a page its title, heading, summary and Usage lines" {
  site out
  run grep -c -e '^<title>hub pull-request</title>$' -e '^<h1>hub pull-request</h1>$' \
    -e '^<p class="summary">Open a pull request for the current branch.</p>$' \
    -e '^<pre class="usage">Usage: hub pull-request \[-fpdoc\] ' out/pull-request.html
  assert_output_equals 4
  run sed -n '/^<pre class="usage">/,/<\/pre>$/p' out/pull-request.html
  local pad='                        '
  local line="${pad}[-F FILE] [-e | --no-edit] [-r LIST] [-a LIST] [-M MILESTONE]"
  assert_line_equals 1 "$line [-l LIST]"
  assert_line_equals 2 "${pad}[--no-maintainer-edits]</pre>"
  run grep -c -e '^<title>hub</title>$' -e '^<h1>hub</h1>$' -e '^<h2>Commands</h2>$' \
    -e '^<h2>More</h2>$' out/index.html
  assert_output_equals 4
  run grep -cxF \
    '<li><a href="https://github.com/brc-dd/hub/blob/main/README.md">README.md</a></li>' \
    out/index.html
  assert_output_equals 1
}

@test "the text of a command page is what hub help prints, and the index's is bin/hub's" {
  local file name
  site out
  for file in "$HUB_TEST_ROOT"/lib/hub/cmd/*.sh; do
    name=${file##*/}
    name=${name%.sh}
    run "$HUB_BIN" help "$name"
    assert_success
    assert_equals "$(main_text "out/$name.html")" "$(manual_text "hub $name" <<<"$output")"
  done
  sed '/^<h2>Commands<\/h2>$/,/^<\/main>$/{/^<\/main>$/!d;}' out/index.html >index-manual.html
  assert_equals "$(main_text index-manual.html)" \
    "$(module_doc "$HUB_TEST_ROOT/bin/hub" | manual_text hub)"
}

@test "site's pages are self-contained HTML with the version and source in the footer" {
  local commit repo=https://github.com/brc-dd/hub
  commit=$(git -C "$HUB_TEST_ROOT" rev-parse HEAD 2>/dev/null) || commit=main
  site out
  run grep -c -e '^<!doctype html>$' -e '^<html lang="en">$' -e '^<meta charset="utf-8">$' \
    -e '^<meta name="viewport" content="width=device-width, initial-scale=1">$' \
    -e '^<meta name="color-scheme" content="light dark">$' -e '^<style>$' \
    -e '^<header><nav><a href="index.html">hub manuals</a></nav></header>$' out/sync.html
  assert_output_equals 7
  run grep -l -i -e '<script' -e '<link' -e 'src=' -e '@import' -e 'url(' out/*.html
  assert_failure
  assert_output_equals ''
  run grep -xF "<footer><p>hub $(<"$HUB_TEST_ROOT/VERSION") &middot; <a href=\"$repo\">\
github.com/brc-dd/hub</a> &middot; source: <a href=\"$repo/blob/$commit/lib/hub/cmd/sync.sh\">\
lib/hub/cmd/sync.sh</a></p></footer>" out/sync.html
  assert_success
  run grep -cF "<a href=\"$repo/blob/$commit/bin/hub\">bin/hub</a>" out/index.html
  assert_output_equals 1
}

@test "site escapes the text, joins paragraphs, finds headings and keeps the indentation" {
  make_fixture
  run fixture/script/site out
  assert_success
  run cat out/zz.html
  assert_output_contains '<title>hub zz</title>'
  assert_output_contains $'<h1>hub zz</h1>\n<p class="summary">A &amp; B &lt;C&gt;</p>\n'
  assert_output_contains $'<pre class="usage">Usage: hub zz [-x] ARG\n       hub zz --long</pre>\n'
  local par='<p>The first line of a paragraph that spans three lines'
  assert_output_contains $'\n'"$par and ends *here* _now_ [a] | b.</p>"$'\n'
  assert_output_contains $'b.</p>\n<p>Second paragraph.</p>\n<h2>Options</h2>\n'
  assert_output_contains $'\n<h2>Options</h2>\n<pre>-x   The x option.\n'
  assert_output_contains $'<pre>-x   The x option.\n  --deep   A deeper line.</pre>\n'
  assert_output_contains $'\n<pre>$ hub zz a\n&gt; cmd &amp;&amp; other</pre>\n</main>\n'
  run grep -cxF '<dt><a href="zz.html">hub zz</a></dt><dd>A &amp; B &lt;C&gt;</dd>' out/index.html
  assert_output_equals 1
}

@test "two runs write the same bytes" {
  site one
  run site two
  assert_success
  run diff -r one two
  assert_success
  assert_output_equals ''
}

@test "site replaces its pages in an existing directory and leaves other files alone" {
  site fresh
  mkdir out
  echo stale >out/sync.html
  echo mine >out/notes.txt
  run site out
  assert_success
  run cmp fresh/sync.html out/sync.html
  assert_success
  assert_equals "$(<out/notes.txt)" mine
}

@test "site creates a missing directory relative to the caller, whatever CDPATH holds" {
  mkdir -p elsewhere decoy/a
  export CDPATH=$HUB_TEST_TMP/decoy
  cd elsewhere || return 1
  run site a/b
  assert_success
  [[ -f a/b/index.html && -f a/b/sync.html && ! -e ../decoy/a/b ]]
}

@test "site without a directory, or with two, is a usage error" {
  run site
  assert_status 1
  assert_output_equals $'script/site: no directory given\nUsage: script/site DIR'
  run --separate-stderr site
  assert_status 1
  assert_output_equals ''
  run site one two
  assert_status 1
  assert_line_equals 0 'script/site: unexpected argument: two'
  run site --bogus
  assert_status 1
  assert_line_equals 0 'script/site: unknown option: --bogus'
  [[ ! -e one && ! -e two ]]
}

@test "site -h and --help print the header" {
  run site -h
  assert_success
  assert_line_equals 0 "Summary: Render hub's manuals as a static website."
  assert_line_equals 1 'Usage: script/site DIR'
  assert_output_lacks 'set -euo'
  run site --help
  assert_success
  assert_line_equals 0 "Summary: Render hub's manuals as a static website."
}

@test "site refuses a manual that does not start with Summary and Usage lines" {
  make_fixture
  printf '# Usage: hub zz\n' >fixture/lib/hub/cmd/zz.sh
  run fixture/script/site out
  assert_status 1
  assert_output_equals \
    'script/site: lib/hub/cmd/zz.sh: the manual does not start with Summary: and Usage: lines'
}

@test "site links the source at main when the sources are not a checkout" {
  git init -q parent
  git -C parent -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m one
  mkdir parent/copy
  cp -R "$HUB_TEST_ROOT"/{bin,lib,script,VERSION,Formula} parent/copy/
  run parent/copy/script/site out
  assert_success
  run grep -c 'blob/main/lib/hub/cmd/sync.sh' out/sync.html
  assert_output_equals 1
  run grep -c "blob/$(git -C parent rev-parse HEAD)/" out/sync.html
  assert_output_equals 0
}

@test "site refuses a DIR that is a file" {
  echo file >out
  run site out
  assert_status 1
  assert_output_equals 'script/site: not a directory: out'
  assert_equals "$(<out)" file
}
