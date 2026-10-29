SHELL := bash
SH_FILES := bin/hub lib/hub/*.sh lib/hub/*/*.sh test/stubs/gh test/*.bash completions/hub.bash $(wildcard script/*)
.PHONY: test lint fmt fmt-check selftest check

test:            ## run the bats test suite
	bats --recursive test

lint:            ## shellcheck everything
	shellcheck --external-sources --shell=bash $(SH_FILES)

fmt:             ## format with shfmt (settings in .editorconfig)
	shfmt -w $(SH_FILES)

fmt-check:       ## fail if shfmt would change anything
	shfmt -d $(SH_FILES)

selftest:        ## run the scripts' built-in self-tests (SemVer comparator)
	script/update-formula --self-test

check: lint fmt-check test selftest

# make install [PREFIX=/usr/local] [DESTDIR=...]
# Symlinks bin/hub into $(PREFIX)/bin (hub follows the link back to lib/hub),
# and the completions into the usual directories when those exist. Anything
# already there that is not one of these links (an old hub, say) is left alone,
# and uninstall only removes links that point into this checkout.
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions
BASH_COMPLETION_DIR ?= $(PREFIX)/etc/bash_completion.d
FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d
HUB_LINKS = '$(CURDIR)/bin/hub' '$(DESTDIR)$(BINDIR)/hub' \
            '$(CURDIR)/completions/hub.zsh' '$(DESTDIR)$(ZSH_COMPLETION_DIR)/_hub' \
            '$(CURDIR)/completions/hub.bash' '$(DESTDIR)$(BASH_COMPLETION_DIR)/hub' \
            '$(CURDIR)/completions/hub.fish' '$(DESTDIR)$(FISH_COMPLETION_DIR)/hub.fish'
.PHONY: install uninstall

install:         ## symlink hub into $(PREFIX)/bin, completions where their directories exist
	mkdir -p '$(DESTDIR)$(BINDIR)'
	@set -- $(HUB_LINKS); while [ $$# -gt 0 ]; do \
	  if [ -d "$$(dirname "$$2")" ]; then \
	    if { [ -e "$$2" ] || [ -L "$$2" ]; } && [ "$$(readlink "$$2")" != "$$1" ]; then \
	      echo "make: $$2 already exists; remove it first" >&2; exit 1; \
	    fi; \
	    echo "ln -sf $$1 $$2"; ln -sf "$$1" "$$2" || exit 1; \
	  fi; shift 2; \
	done

uninstall:       ## remove the links that install made
	@set -- $(HUB_LINKS); while [ $$# -gt 0 ]; do \
	  case "$$(readlink "$$2" 2>/dev/null)" in "$$1") echo "rm $$2"; rm -f "$$2" || exit 1 ;; esac; shift 2; \
	done
