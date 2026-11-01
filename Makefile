SHELL := bash

STUB_LINKS := test/stubs/open test/stubs/xdg-open test/stubs/xclip test/stubs/wl-copy
SH_FILES := $(wildcard bin/hub lib/hub/*.sh lib/hub/cmd/*.sh script/* completions/hub.bash) \
	$(filter-out $(STUB_LINKS),$(wildcard test/stubs/*)) $(wildcard test/*.bash)
BATS_FILES := $(wildcard test/*.bats)
WORKFLOWS := $(wildcard .github/workflows/*.yml)

.PHONY: test lint fmt fmt-check selftest check site install uninstall

test:
	bats test

lint:
	shellcheck --external-sources --shell=bash $(SH_FILES)
	shellcheck --external-sources --shell=bash --severity=warning $(BATS_FILES)
	@awk 'length > 100 { print FILENAME ":" FNR ": longer than 100 columns"; bad = 1 } \
	  END { exit bad }' Makefile $(SH_FILES) $(BATS_FILES) $(WORKFLOWS) .github/dependabot.yml
	@if command -v actionlint >/dev/null; then actionlint $(WORKFLOWS); \
	  else echo 'make lint: actionlint is not installed; the workflows were not linted' >&2; fi

fmt:
	shfmt -w $(SH_FILES) $(BATS_FILES)

fmt-check:
	shfmt -d $(SH_FILES) $(BATS_FILES)

selftest:
	script/update-formula --self-test

check: lint fmt-check test selftest

site:
	script/site site

# make install [PREFIX=/usr/local] [DESTDIR=...]: links bin/hub into BINDIR and each completion
# that exists into its directory when that directory exists. A destination that is not already
# hub's link is an error; uninstall removes only links into this checkout. Write
# PREFIX="$HOME/.local", not ~/.local: make does not expand a ~. The paths reach the recipe
# through the environment, so spaces and quotes in them stay literal.
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
BASH_COMPLETION_DIR ?= $(PREFIX)/etc/bash_completion.d
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions
FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d

install uninstall: export HUB_SRC := $(CURDIR)
install uninstall: export HUB_DESTDIR := $(DESTDIR)
install uninstall: export HUB_BINDIR := $(BINDIR)
install uninstall: export HUB_BASHDIR := $(BASH_COMPLETION_DIR)
install uninstall: export HUB_ZSHDIR := $(ZSH_COMPLETION_DIR)
install uninstall: export HUB_FISHDIR := $(FISH_COMPLETION_DIR)

# Sets the positional parameters to SOURCE DESTINATION-DIRECTORY NAME triples.
HUB_LINKS = for dir in "$$HUB_DESTDIR" "$$HUB_BINDIR" "$$HUB_BASHDIR" "$$HUB_ZSHDIR" \
	  "$$HUB_FISHDIR"; do \
	  if [[ $$dir == '~'* ]]; then \
	    echo "make: $$dir starts with a literal ~; write PREFIX=\"\$$HOME/...\"" >&2; exit 1; \
	  fi; \
	done; \
	set -- "$$HUB_SRC/bin/hub" "$$HUB_DESTDIR$$HUB_BINDIR" hub \
	  "$$HUB_SRC/completions/hub.bash" "$$HUB_DESTDIR$$HUB_BASHDIR" hub \
	  "$$HUB_SRC/completions/hub.zsh" "$$HUB_DESTDIR$$HUB_ZSHDIR" _hub \
	  "$$HUB_SRC/completions/hub.fish" "$$HUB_DESTDIR$$HUB_FISHDIR" hub.fish

install:
	@$(HUB_LINKS); mkdir -p -- "$$2" || exit; \
	while (($$#)); do \
	  dest=$$2/$$3; \
	  if [[ ! -e $$1 || $$(readlink -- "$$dest") == "$$1" ]]; then :; \
	  elif [[ -e $$dest || -L $$dest ]]; then \
	    echo "make install: $$dest exists and is not a link to $$1" >&2; exit 1; \
	  elif [[ -d $$2 ]]; then \
	    printf 'ln -s %q %q\n' "$$1" "$$dest"; ln -s -- "$$1" "$$dest" || exit; \
	  fi; \
	  shift 3; \
	done

uninstall:
	@$(HUB_LINKS); \
	while (($$#)); do \
	  dest=$$2/$$3; \
	  if [[ $$(readlink -- "$$dest") == "$$1" ]]; then \
	    printf 'rm %q\n' "$$dest"; rm -- "$$dest" || exit; \
	  fi; \
	  shift 3; \
	done
