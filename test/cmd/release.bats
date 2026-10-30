#!/usr/bin/env bats
load ../test_helper

@test "release with no arguments lists releases" {
  run hub --noop release
  assert_success
  assert_output_equals "gh release list"
  assert_gh_not_called
}

@test "release with only options lists releases with them" {
  run hub --noop release -L 5 --exclude-drafts
  assert_success
  assert_output_equals "gh release list -L 5 --exclude-drafts"
}

@test "release show is gh release view" {
  run hub --noop release show v1.0 --json tagName,assets
  assert_success
  assert_output_equals "gh release view v1.0 --json tagName,assets"
}

@test "release passes gh's other subcommands through unchanged, in order" {
  run hub --noop release delete v1.0 -y --cleanup-tag
  assert_success
  assert_output_equals "gh release delete v1.0 -y --cleanup-tag"
  run hub --noop release upload v1.0 a.tgz --clobber
  assert_success
  assert_output_equals "gh release upload v1.0 a.tgz --clobber"
  run hub --noop release list -O asc --some-new-flag
  assert_success
  assert_output_equals "gh release list -O asc --some-new-flag"
}

@test "release keeps -R given before the subcommand" {
  touch a.tgz
  run hub --noop release -R mislav/dotfiles delete v1.0
  assert_success
  assert_output_equals "gh release delete -R mislav/dotfiles v1.0"
  run hub --noop release -R mislav/dotfiles create v1.0 -a a.tgz
  assert_success
  assert_output_equals "gh release create -R mislav/dotfiles v1.0 a.tgz"
}

@test "release create turns -a files into asset arguments, keeping #labels" {
  touch a.tgz b.zip
  run hub --noop release create v1.0 -a a.tgz -a 'b.zip#Label'
  assert_success
  assert_output_equals "gh release create v1.0 a.tgz b.zip#Label"
}

@test "release create accepts --attach, --attach= and -aFILE, before or after the tag" {
  touch a.tgz b.zip c.txt
  run hub --noop release create --attach a.tgz --attach=b.zip -ac.txt v1.0 d.txt
  assert_success
  assert_output_equals "gh release create v1.0 d.txt a.tgz b.zip c.txt"
}

@test "release create -a without a tag aborts rather than taking a file for the tag" {
  run hub --noop release create -a a.tgz -d
  assert_failure
  assert_output_contains "Usage: hub release create TAG"
}

@test "release create -m with only a title sends empty notes" {
  run hub --noop release create v1.0 -m v1.0
  assert_success
  assert_output_equals "gh release create v1.0 --title v1.0 --notes ''"
}

@test "release create -m splits the title from the notes" {
  run hub --noop release create v1.0 -m $'Version 1.0\n\nFirst release.\n\n- fast'
  assert_success
  assert_output_equals "gh release create v1.0 --title Version\\ 1.0 --notes \$'First release.\\n\\n- fast'"
}

@test "release create joins repeated -m values as paragraphs" {
  run hub --noop release create v1.0 -m "Version 1.0" -m First -m Second
  assert_success
  assert_output_equals "gh release create v1.0 --title Version\\ 1.0 --notes \$'First\\n\\nSecond'"
  run hub --noop release create v1.0 -m "Version 1.0" --message First --message=Second
  assert_success
  assert_output_equals "gh release create v1.0 --title Version\\ 1.0 --notes \$'First\\n\\nSecond'"
}

@test "release create -F reads the title and notes from a file" {
  printf 'Version 1.0\n\nFirst release.\n' >notes.txt
  run hub --noop release create v1.0 -F notes.txt
  assert_success
  assert_output_equals "gh release create v1.0 --title Version\\ 1.0 --notes First\\ release."
  printf 'Version 1.0\n' >title.txt
  run hub --noop release create v1.0 --file title.txt
  assert_success
  assert_output_equals "gh release create v1.0 --title Version\\ 1.0 --notes ''"
}

@test "release create -F - reads the title and notes from standard input" {
  run hub --noop release create v1.0 -F - <<<$'v1.0\n\nFirst release.'
  assert_success
  assert_output_equals "gh release create v1.0 --title v1.0 --notes First\\ release."
}

@test "release create -t and --commitish become --target" {
  run hub --noop release create v1.0 -t main
  assert_success
  assert_output_equals "gh release create v1.0 --target main"
  run hub --noop release create v1.0 --commitish=release-1.0 -tdev
  assert_success
  assert_output_equals "gh release create v1.0 --target release-1.0 --target dev"
}

@test "release create keeps -d, -p and gh's own options unchanged, in order" {
  run hub --noop release create -d -p v1.0 --title T --notes N --target main --latest=false --verify-tag
  assert_success
  assert_output_equals "gh release create -d -p v1.0 --title T --notes N --target main --latest=false --verify-tag"
}

@test "release create puts --title/--notes where -m was" {
  mkdir dist && touch dist/app.tgz dist/app.zip
  run hub --noop release create -d -m v1.2.0 -a dist/app.tgz -a 'dist/app.zip#Archive' v1.2.0
  assert_success
  assert_output_equals "gh release create -d --title v1.2.0 --notes '' v1.2.0 dist/app.tgz dist/app.zip#Archive"
}

@test "release create -m with gh's own notes options adds no empty notes" {
  run hub --noop release create v1.0 -m v1.0 --generate-notes
  assert_success
  assert_output_equals "gh release create v1.0 --title v1.0 --generate-notes"
  run hub --noop release create v1.0 -m v1.0 --notes-file CHANGES.md
  assert_success
  assert_output_equals "gh release create v1.0 --title v1.0 --notes-file CHANGES.md"
}

@test "release create drops the '=' of -m=, -F=, -t= and -a= values, as gh's parser does" {
  touch a.tgz
  run hub --noop release create v1 -m=Title -t=main -a=a.tgz
  assert_success
  assert_output_equals "gh release create v1 --title Title --notes '' --target main a.tgz"
  printf 'Version 1.0\n\nFirst release.\n' >notes.txt
  run hub --noop release create v1 -F=notes.txt -t==main # only one '='
  assert_success
  assert_output_equals "gh release create v1 --title Version\\ 1.0 --notes First\\ release. --target =main"
  run hub --noop release create v1 -m=Title -n=Notes -R=mislav/dotfiles # gh's own options go as typed
  assert_success
  assert_output_equals "gh release create v1 --title Title -n=Notes -R=mislav/dotfiles"
}

@test "release create does not take option values for hub's options" {
  run hub --noop release create v1.0 --notes -mnot-a-message --title -a
  assert_success
  assert_output_equals "gh release create v1.0 --notes -mnot-a-message --title -a"
}

@test "release create aborts on -m with -F or a missing value" {
  printf 'v1.0\n' >notes.txt
  run hub --noop release create v1.0 -m v1.0 -F notes.txt
  assert_failure
  assert_output_equals "Aborted: -m and -F cannot be used together."
  run hub --noop release create v1.0 -a
  assert_failure
  assert_output_equals "Aborted: -a needs a value."
}

@test "release edit -a uploads the files with gh release upload, which won't replace assets" {
  touch a.tgz b.zip
  run hub --noop release edit v1.0 -a a.tgz -a 'b.zip#Label'
  assert_success
  assert_output_equals "gh release upload v1.0 a.tgz b.zip#Label"
}

@test "release edit -a replaces assets of the same name only with --clobber" {
  touch a.tgz
  run hub --noop release edit v1.0 -a a.tgz --clobber
  assert_success
  assert_output_equals "gh release upload v1.0 a.tgz --clobber"
  run hub --noop release edit v1.0 --clobber=false -a a.tgz
  assert_success
  assert_output_equals "gh release upload v1.0 a.tgz --clobber=false"
}

@test "release edit --clobber without -a is left to gh" {
  run hub --noop release edit v1.0 -m "New title" --clobber
  assert_success
  assert_output_equals "gh release edit v1.0 --title New\\ title --clobber"
}

@test "release edit -a with other options edits first, with hub's -m and -t translated" {
  touch a.tgz
  run hub --noop release edit v1.0 -m "New title" -t main -a a.tgz
  assert_success
  assert_output_equals $'gh release edit v1.0 --title New\\ title --target main\ngh release upload v1.0 a.tgz'
}

@test "release edit -m leaves out an empty title or empty notes" {
  run hub --noop release edit v1.0 -m "New title"
  assert_success
  assert_output_equals "gh release edit v1.0 --title New\\ title"
  touch a.tgz
  run hub --noop release edit v1.0 -m "" -a a.tgz
  assert_success
  assert_output_equals "gh release upload v1.0 a.tgz"
}

@test "release edit -F reads the title and notes from a file" {
  printf 'Version 1.0\n\nFirst release.\n' >notes.txt
  run hub --noop release edit v1.0 -F notes.txt --latest
  assert_success
  assert_output_equals "gh release edit v1.0 --title Version\\ 1.0 --notes First\\ release. --latest"
}

@test "release edit drops the '=' of -m=, -F=, -t= and -a= values, as gh's parser does" {
  touch a.tgz
  run hub --noop release edit v1.0 -m=Title -t=main -a=a.tgz -R=mislav/dotfiles
  assert_success
  assert_output_equals $'gh release edit v1.0 --title Title --target main -R=mislav/dotfiles\ngh release upload v1.0 a.tgz -R=mislav/dotfiles'
  printf 'Version 1.0\n\nFirst release.\n' >notes.txt
  run hub --noop release edit v1.0 -F=notes.txt
  assert_success
  assert_output_equals "gh release edit v1.0 --title Version\\ 1.0 --notes First\\ release."
}

@test "release edit spells out -d and -p, which gh's edit lacks" {
  run hub --noop release edit v1.0 -d -p
  assert_success
  assert_output_equals "gh release edit v1.0 --draft --prerelease"
  run hub --noop release edit v1.0 --draft=false --prerelease=false
  assert_success
  assert_output_equals "gh release edit v1.0 --draft=false --prerelease=false"
}

@test "release edit without -a is gh release edit with gh's options unchanged" {
  run hub --noop release edit v1.0 --notes-file CHANGES.md --title T --some-new-flag
  assert_success
  assert_output_equals "gh release edit v1.0 --notes-file CHANGES.md --title T --some-new-flag"
}

@test "release edit gives -R to both edit and upload, and uploads to a --tag rename" {
  touch a.tgz
  run hub --noop release edit v1.0 -R mislav/dotfiles -m T -a a.tgz --clobber
  assert_success
  assert_output_equals $'gh release edit v1.0 -R mislav/dotfiles --title T\ngh release upload v1.0 a.tgz --clobber -R mislav/dotfiles'
  run hub --noop release edit v1.0 --tag v1.0.1 -a a.tgz
  assert_success
  assert_output_equals $'gh release edit v1.0 --tag v1.0.1\ngh release upload v1.0.1 a.tgz'
}

@test "release edit -a without a tag aborts" {
  run hub --noop release edit -a a.tgz
  assert_failure
  assert_output_contains "Usage: hub release edit TAG"
}

@test "release edit does not upload when the edit fails" {
  touch a.tgz
  stub_gh 'release edit v1.0 --draft' 'release not found' 1
  stub_gh 'release upload *' ''
  run hub release edit v1.0 -d -a a.tgz
  assert_failure
  assert_output_equals "release not found"
  assert_gh_called 'release edit v1.0 --draft'
  [[ $(gh_calls) != *"release upload"* ]]
}

@test "release edit runs gh release edit, then gh release upload" {
  touch a.tgz
  stub_gh 'release edit v1.0 *' 'https://github.com/mislav/dotfiles/releases/tag/v1.0'
  stub_gh 'release upload v1.0 a.tgz' ''
  run hub release edit v1.0 -d -a a.tgz
  assert_success
  assert_output_equals "https://github.com/mislav/dotfiles/releases/tag/v1.0"
  [[ $(gh_calls) == $'gh release edit v1.0 --draft\ngh release upload v1.0 a.tgz' ]]
}

@test "release edit checks every -a file before running gh" {
  touch a.tgz
  mkdir adir
  run hub --noop release edit v1.0 --title Changed -a /nonexistent
  assert_failure
  assert_output_equals "Aborted: cannot read /nonexistent"
  run hub release edit v1.0 --title Changed -a a.tgz -a 'missing.zip#Label' -a adir -a 'two words.tgz'
  assert_failure
  assert_output_equals "Aborted: cannot read missing.zip, adir, two\\ words.tgz"
  assert_gh_not_called
}

@test "release edit -a refuses an unreadable file" {
  [[ $(id -u) != 0 ]] || skip "root can read any file"
  touch secret.tgz
  chmod 000 secret.tgz
  run hub release edit v1.0 -d -a secret.tgz
  assert_failure
  assert_output_equals "Aborted: cannot read secret.tgz"
  assert_gh_not_called
}

@test "release create checks every -a file before running gh" {
  touch a.tgz
  run hub --noop release create v1.0 -d -a missing.tgz
  assert_failure
  assert_output_equals "Aborted: cannot read missing.tgz"
  run hub release create v1.0 -a a.tgz -a 'missing.zip#Label' -a /nonexistent/b.tgz
  assert_failure
  assert_output_equals "Aborted: cannot read missing.zip, /nonexistent/b.tgz"
  assert_gh_not_called
}

@test "release -a splits FILE#LABEL at the first '#' unless it starts the name, as gh does" {
  touch a.tgz '#odd.tgz'
  run hub --noop release create v1.0 -a 'a.tgz#Label #1' -a 'a.tgz#' -a '#odd.tgz'
  assert_success
  assert_output_equals "gh release create v1.0 a.tgz#Label\\ #1 a.tgz# \\#odd.tgz"
  run hub --noop release edit v1.0 -a '#odd.tgz#Label' # gh takes it all as the file name
  assert_failure
  assert_output_equals "Aborted: cannot read \\#odd.tgz#Label"
}

@test "release -a without a #LABEL may be a glob pattern for gh, which must match" {
  mkdir dist && touch dist/a.tgz dist/b.tgz
  run hub --noop release create v1.0 -a 'dist/*.tgz'
  assert_success
  assert_output_equals "gh release create v1.0 dist/\\*.tgz"
  run hub --noop release edit v1.0 --title T -a 'dist/*.zip'
  assert_failure
  assert_output_equals "Aborted: cannot read dist/\\*.zip"
}

@test "release download -i becomes -p" {
  run hub --noop release download v1.0 -i '*.tgz' -i '*.zip'
  assert_success
  assert_output_equals "gh release download v1.0 -p \\*.tgz -p \\*.zip"
  run hub --noop release download v1.0 --include=*.deb -D dist
  assert_success
  assert_output_equals "gh release download v1.0 -p \\*.deb -D dist"
}

@test "release download drops the '=' of an -i= value, as gh's parser does" {
  run hub --noop release download v1.0 '-i=*.tgz' -i==odd '-p=*.zip' -D=dist
  assert_success
  assert_output_equals "gh release download v1.0 -p \\*.tgz -p =odd -p=\\*.zip -D=dist"
}

@test "release download keeps gh's own options unchanged" {
  run hub --noop release download v1.0 -p '*.tgz' --clobber -O - -A zip
  assert_success
  assert_output_equals "gh release download v1.0 -p \\*.tgz --clobber -O - -A zip"
}

@test "release runs gh with the mapped arguments" {
  stub_gh 'release list' 'v1.0\tLatest'
  run hub release
  assert_success
  assert_output_equals $'v1.0\tLatest'
  assert_gh_called 'release list'
}

@test "release -h and --help print the manual, also after hub's subcommands" {
  run hub release --help
  assert_success
  assert_output_contains "Usage: hub release"
  run hub --noop release create v1.0 -h
  assert_success
  assert_output_contains "-a, --attach FILE[#LABEL]"
  assert_output_contains "--clobber"
  run hub --noop release edit v1.0 --help
  assert_success
  assert_output_contains "Usage: hub release"
  run hub --noop release download v1.0 --help
  assert_success
  assert_output_contains "Usage: hub release"
  run hub help release
  assert_success
  assert_output_contains "Usage: hub release"
  assert_gh_not_called
}

@test "release SUBCOMMAND --help for gh's own subcommands is gh's help" {
  run hub --noop release delete --help
  assert_success
  assert_output_equals "gh release delete --help"
}
