SHELL := bash
SH_FILES := bin/hub lib/hub/*.sh lib/hub/*/*.sh test/stubs/* test/*.bash completions/hub.bash $(wildcard script/*)
BATS_FILES := test/*.bats test/*/*.bats
.PHONY: test lint fmt fmt-check selftest check install uninstall

test:
	bats --recursive test

lint:
	shellcheck --external-sources --shell=bash $(SH_FILES)
	shellcheck --external-sources --shell=bash --severity=warning $(BATS_FILES)

fmt:
	shfmt -w $(SH_FILES) $(BATS_FILES)

fmt-check:
	shfmt -d $(SH_FILES) $(BATS_FILES)

selftest:
	script/update-formula --self-test

check: lint fmt-check test selftest

# make install [PREFIX=/usr/local]: symlinks bin/hub into $(BINDIR) and the completions into
# those of the completion directories that exist. Nothing but these links is ever created or
# removed: a file or directory already at a destination is an error, and make uninstall removes
# a link only when it points into this checkout. Write PREFIX="$HOME/.local", not ~/.local: zsh
# and sh pass the ~ on literally, and make does not expand it.
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions
BASH_COMPLETION_DIR ?= $(PREFIX)/etc/bash_completion.d
FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d

# The paths reach the recipes through the environment, never through the command text, so that
# spaces, quotes and backquotes in them stay literal (make itself still reads $: write $$).
export HUB_SRC := $(CURDIR)
export HUB_BIN := $(DESTDIR)$(BINDIR)
export HUB_ZSH := $(DESTDIR)$(ZSH_COMPLETION_DIR)
export HUB_BASH := $(DESTDIR)$(BASH_COMPLETION_DIR)
export HUB_FISH := $(DESTDIR)$(FISH_COMPLETION_DIR)
# The recipes loop over SOURCE DIRECTORY NAME triples.
HUB_LINKS = for dir in "$$HUB_BIN" "$$HUB_ZSH" "$$HUB_BASH" "$$HUB_FISH"; do \
	      case $$dir in '~'*) echo "make: $$dir starts with a literal ~ (the shell did not expand it); write PREFIX=\"\$$HOME/...\"" >&2; exit 1 ;; esac; \
	    done; \
	    set -- "$$HUB_SRC/bin/hub" "$$HUB_BIN" hub \
	           "$$HUB_SRC/completions/hub.zsh" "$$HUB_ZSH" _hub \
	           "$$HUB_SRC/completions/hub.bash" "$$HUB_BASH" hub \
	           "$$HUB_SRC/completions/hub.fish" "$$HUB_FISH" hub.fish

install:
	@$(HUB_LINKS); mkdir -p -- "$$HUB_BIN" || exit; \
	while [ $$# -gt 0 ]; do \
	  dest=$$2/$$3; \
	  if [ "$$(readlink "$$dest")" = "$$1" ]; then :; \
	  elif [ -e "$$dest" ] || [ -L "$$dest" ]; then \
	    echo "make install: $$dest exists and is not a link to $$1" >&2; exit 1; \
	  elif [ -d "$$2" ]; then \
	    printf 'ln -s %q %q\n' "$$1" "$$dest"; ln -s -- "$$1" "$$dest" || exit; \
	  fi; shift 3; \
	done

uninstall:
	@$(HUB_LINKS); while [ $$# -gt 0 ]; do \
	  dest=$$2/$$3; \
	  if [ "$$(readlink "$$dest")" = "$$1" ]; then printf 'rm %q\n' "$$dest"; rm -- "$$dest" || exit; fi; \
	  shift 3; \
	done
