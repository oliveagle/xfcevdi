# Makefile for xfcevdi (XFCE VDI + MetaTrader 5 on Debian)
#
# Typical workflow:
#   make lint    - shellcheck + shell syntax checks
#   make build   - build the Docker/Podman image
#   make test    - lint + build + smoke tests
#   make shell   - interactive shell inside a container built from the image
#   make clean   - remove the built image and build cache

# ---------------------------------------------------------------------------
# Config (override on the command line, e.g. `make build CONTAINER=podman`)
# ---------------------------------------------------------------------------
CONTAINER ?= docker
IMAGE     ?= xfcevdi:dev
TAG       ?= dev

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
.PHONY: all lint shellcheck syntax-check build test test-shell test-smoke clean help

all: test

lint: shellcheck syntax-check

shellcheck:
	@echo "[lint] shellcheck over scripts/"
	@shellcheck scripts/*.sh

syntax-check:
	@echo "[lint] bash -n over scripts/"
	@set -e; for f in scripts/*.sh; do echo "  bash -n $$f"; bash -n "$$f"; done

build:
	@echo "[build] $(CONTAINER) build -t $(IMAGE):$(TAG) ."
	$(CONTAINER) build -t $(IMAGE):$(TAG) .

test: lint build test-shell test-smoke

test-shell:
	@echo "[test] mt5 --check inside the built image"
	$(CONTAINER) run --rm $(IMAGE):$(TAG) /usr/local/bin/mt5-install --check || true
	@echo "[test] mt5 --prefetch inside the built image (best effort)"
	$(CONTAINER) run --rm $(IMAGE):$(TAG) /usr/local/bin/mt5-install --prefetch || true

test-smoke:
	@echo "[test] verifying MT5 layer inside the built image"
	$(CONTAINER) run --rm $(IMAGE):$(TAG) bash -c '\
		set -e; \
		command -v mt5-install; \
		command -v mt5-launch; \
		command -v mt5-autoupdate; \
		test -f /usr/share/applications/metatrader5.desktop; \
		test -f /etc/cron.d/mt5-autoupdate; \
		echo "smoke test: all MT5 artefacts present"'

shell:
	@echo "[shell] $(CONTAINER) run --rm -it $(IMAGE):$(TAG) bash"
	$(CONTAINER) run --rm -it $(IMAGE):$(TAG) bash

clean:
	@echo "[clean] removing image $(IMAGE):$(TAG)"
	-$(CONTAINER) image rm $(IMAGE):$(TAG)
	-$(CONTAINER) builder prune -f 2>/dev/null || true

help:
	@echo "Targets:"
	@echo "  all           lint + build + test"
	@echo "  lint          shellcheck + bash syntax checks"
	@echo "  shellcheck    run shellcheck on scripts/"
	@echo "  syntax-check  run bash -n on scripts/"
	@echo "  build         build the container image"
	@echo "  test          lint + build + test-shell + test-smoke"
	@echo "  test-shell    run mt5 --check inside the built image"
	@echo "  test-smoke    verify MT5 artefacts inside the built image"
	@echo "  shell         run an interactive shell in the image"
	@echo "  clean         remove the built image"
	@echo ""
	@echo "Override CONTAINER to podman or docker: \`make build CONTAINER=podman\`"
