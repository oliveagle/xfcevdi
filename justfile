# justfile for xfcevdi developer workflow
# Usage: just <recipe>

default:
    @just --list

# Build the image (override CONTAINER=podman|docker)
[private]
build container="docker":
    {{container}} build -t xfcevdi:dev .

# Lint all shell scripts
[private]
lint:
    shellcheck scripts/*.sh
    @bash -c 'set -e; for f in scripts/*.sh; do echo "bash -n $f"; bash -n "$f"; done'

# Lint + build + smoke test
test: lint build
    {{container}} run --rm xfcevdi:dev /usr/local/bin/mt5-install --check || true
    {{container}} run --rm xfcevdi:dev bash -c 'set -e; command -v mt5-install; command -v mt5-launch; command -v mt5-autoupdate; echo "smoke OK"'

# Interactive shell in the image
[private]
shell container="docker":
    {{container}} run --rm -it xfcevdi:dev bash

# Clean up
[private]
clean container="docker":
    {{container}} image rm xfcevdi:dev || true
