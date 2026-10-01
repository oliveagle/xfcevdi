#!/usr/bin/env bash
# Compile-and-test smoke: proves the image's dev toolchain works.
# gcc, cmake, pytest and shellcheck must all be usable inside the container.
set -euo pipefail

CONTAINER="${CONTAINER:-docker}"
IMAGE="${IMAGE:-xfcevdi}"
TAG="${TAG:-dev}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[test_toolchain] compiling with gcc -Wall -Werror"
"${CONTAINER}" run --rm -v "${DIR}/fixtures:/src:ro" --entrypoint /bin/bash "${IMAGE}:${TAG}" -c '
set -euo pipefail
cd /tmp
gcc -Wall -Wextra -Werror -O2 /src/hello.c -o /tmp/hello
/tmp/hello

echo "[test_toolchain] cmake configure + build + ctest"
cp /src/CMakeLists.txt /src/hello.c /tmp/
cd /tmp
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build >/dev/null
ctest --test-dir build --output-on-failure

echo "[test_toolchain] pytest"
cp /src/test_add.py /tmp/
python3 -m pytest -q /tmp/test_add.py

echo "[test_toolchain] cppcheck"
cppcheck --error-exitcode=1 --enable=warning /src/hello.c 2>/dev/null

echo "[test_toolchain] OK"
'
