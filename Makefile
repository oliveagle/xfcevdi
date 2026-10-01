# Makefile for xfcevdi (XFCE VDI + MetaTrader 5 on Debian)
#
# Typical workflow:
#   make lint    - shellcheck + shell syntax checks
#   make build   - build the Docker/Podman image
#   make test    - lint + build + smoke tests + toolchain + MT5 logic
#   make shell   - interactive shell inside a container built from the image
#   make clean   - remove the built image and build cache

CONTAINER ?= docker
IMAGE     ?= xfcevdi
TAG       ?= dev
REF       := $(IMAGE):$(TAG)

.PHONY: all lint shellcheck syntax-check build test test-shell test-smoke test-toolchain test-cron test-mt5 clean help

all: test

lint: shellcheck syntax-check

shellcheck:
	@echo "[lint] shellcheck over scripts/"
	@shellcheck scripts/*.sh

syntax-check:
	@echo "[lint] bash -n over scripts/"
	@set -e; for f in scripts/*.sh; do echo "  bash -n $$f"; bash -n "$$f"; done

build:
	@echo "[build] $(CONTAINER) build -t $(REF) ."
	$(CONTAINER) build -t $(REF) .

test: lint build test-shell test-smoke test-toolchain test-cron test-mt5

test-shell:
	@echo "[test] mt5 --check / --prefetch inside the built image"
	$(CONTAINER) run --rm $(REF) /usr/local/bin/mt5-install --check || true
	$(CONTAINER) run --rm $(REF) /usr/local/bin/mt5-install --prefetch || true

test-smoke:
	@echo "[test] verifying MT5 artefacts inside the built image"
	$(CONTAINER) run --rm $(REF) bash -c '\
		set -e; \
		command -v mt5-install; \
		command -v mt5-launch; \
		command -v mt5-autoupdate; \
		test -f /usr/share/applications/metatrader5.desktop; \
		test -f /etc/cron.d/mt5-autoupdate; \
		echo "smoke test: all MT5 artefacts present"'

test-toolchain:
	@echo "[test] compile & test toolchain inside the built image"
	bash tests/test_toolchain.sh

test-cron:
	@echo "[test] first-boot setup (user + MT5 cron)"
	bash tests/test_setup_cron.sh

test-mt5:
	@echo "[test] MT5 auto-upgrade logic inside the built image"
	$(CONTAINER) run --rm -v "$(CURDIR)/tests:/tests:ro" --entrypoint /bin/bash $(REF) -c 'bash /tests/test_mt5_install.sh'

shell:
	@echo "[shell] $(CONTAINER) run --rm -it $(REF) bash"
	$(CONTAINER) run --rm -it $(REF) bash

clean:
	@echo "[clean] removing image $(REF)"
	-$(CONTAINER) image rm $(REF)
	-$(CONTAINER) builder prune -f 2>/dev/null || true

help:
	@echo "Targets:"
	@echo "  all             lint + build + test"
	@echo "  lint            shellcheck + bash syntax checks"
	@echo "  shellcheck      run shellcheck on scripts/"
	@echo "  syntax-check    run bash -n on scripts/"
	@echo "  build           build the container image"
	@echo "  test            lint + build + all runtime tests"
	@echo "  test-shell      run mt5 --check / --prefetch inside the built image"
	@echo "  test-smoke      verify MT5 artefacts inside the built image"
	@echo "  test-toolchain  compile & test inside the built image"
	@echo "  test-cron       verify first-boot setup writes user-scoped MT5 cron"
	@echo "  test-mt5        verify MT5 auto-upgrade idempotence logic"
	@echo "  shell           run an interactive shell in the image"
	@echo "  clean           remove the built image"
	@echo ""
	@echo "Override CONTAINER to podman or docker: \`make build CONTAINER=podman\`"
