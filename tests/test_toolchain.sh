#!/usr/bin/env bash
# Compile-and-test smoke: proves the image's dev toolchain works.
# gcc, cmake and cppcheck must be usable inside the container (pytest is
# intentionally absent from the no-Python production image and is skipped).
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

echo "[test_toolchain] pytest (optional; production image has no Python)"
cp /src/test_add.py /tmp/
if python3 -m pytest -q /tmp/test_add.py 2>/dev/null; then
  echo "[test_toolchain] pytest OK"
else
  echo "[test_toolchain] pytest skipped (not installed by design: no-Python prod image)"
fi

echo "[test_toolchain] cppcheck"
cppcheck --error-exitcode=1 --enable=warning /src/hello.c 2>/dev/null

echo "[test_toolchain] OK"
'
