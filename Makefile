SHELL := bash
SH_FILES := bin/hub lib/hub/*.sh lib/hub/*/*.sh test/stubs/gh test/*.bash completions/hub.bash $(wildcard script/*)
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

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions
BASH_COMPLETION_DIR ?= $(PREFIX)/etc/bash_completion.d
FISH_COMPLETION_DIR ?= $(PREFIX)/share/fish/vendor_completions.d
HUB_LINKS = '$(CURDIR)/bin/hub' '$(DESTDIR)$(BINDIR)/hub' \
            '$(CURDIR)/completions/hub.zsh' '$(DESTDIR)$(ZSH_COMPLETION_DIR)/_hub' \
            '$(CURDIR)/completions/hub.bash' '$(DESTDIR)$(BASH_COMPLETION_DIR)/hub' \
            '$(CURDIR)/completions/hub.fish' '$(DESTDIR)$(FISH_COMPLETION_DIR)/hub.fish'

# Completions are linked only into directories that exist, and nothing is ever
# replaced but these links: ln -s without -f fails instead.
install:
	mkdir -p '$(DESTDIR)$(BINDIR)'
	@set -- $(HUB_LINKS); while [ $$# -gt 0 ]; do \
	  if [ -d "$$(dirname "$$2")" ] && [ "$$(readlink "$$2")" != "$$1" ]; then \
	    echo "ln -s $$1 $$2" && ln -s "$$1" "$$2" || exit; \
	  fi; shift 2; \
	done

uninstall:
	@set -- $(HUB_LINKS); while [ $$# -gt 0 ]; do \
	  if [ "$$(readlink "$$2")" = "$$1" ]; then echo "rm $$2" && rm "$$2" || exit; fi; shift 2; \
	done
