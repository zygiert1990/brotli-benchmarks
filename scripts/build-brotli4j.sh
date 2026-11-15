#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/build-brotli4j.sh [--jni-only] BROTLI4J_REPO COMMIT VERSION

Builds brotli4j, service and the native library of one commit and installs them into the Maven
local repository as VERSION. The commit is checked out in a temporary git worktree, so the
checkout in BROTLI4J_REPO is left alone. Every target is built this way, with the same JDK and C
toolchain, so differences between targets come from the code, not from different builds.

Examples:
  scripts/build-brotli4j.sh --jni-only ~/forks/Brotli4j 0a0ac32 1.24.0-MAIN   # main, JNI only
  scripts/build-brotli4j.sh ~/forks/Brotli4j add-support-for-ffm-api 1.24.0-LOCAL

--jni-only  The commit has no FFM code (see install-local-brotli4j.sh).

Needs cmake and a C/C++ compiler on PATH, as the brotli4j native build does.
EOF
}

declare -a INSTALL_OPTIONS=()
if [[ ${1:-} == --jni-only ]]; then
    INSTALL_OPTIONS=(--jni-only)
    shift
fi
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
    usage
    exit 0
fi
if (( $# != 3 )); then
    usage >&2
    exit 2
fi

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/common.sh"

readonly REPO=$(cd -- "$1" && pwd)
readonly VERSION=$3
COMMIT=$(git -C "$REPO" rev-parse --verify --quiet "$2^{commit}") || {
    echo "Error: $2 is not a commit in $REPO." >&2
    exit 2
}
readonly COMMIT

for command in git mvn cmake make cc c++; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command is unavailable: $command" >&2
        exit 1
    fi
done

WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/brotli4j-$VERSION-XXXXXX")
readonly WORKTREE
remove_worktree() {
    git -C "$REPO" worktree remove --force "$WORKTREE" >/dev/null 2>&1 || rm -rf -- "$WORKTREE"
    git -C "$REPO" worktree prune
}
trap remove_worktree EXIT

echo "Building $COMMIT from $REPO as $VERSION in $WORKTREE"
git -C "$REPO" worktree add --detach --quiet "$WORKTREE" "$COMMIT"
(cd -- "$WORKTREE" && mvn -q -B -ntp -pl "brotli4j,service,natives/$NATIVE_PLATFORM" -am -DskipTests package)
"$SCRIPT_DIR/install-local-brotli4j.sh" "${INSTALL_OPTIONS[@]}" "$WORKTREE" "$VERSION" "$NATIVE_PLATFORM"
echo "Built from commit $COMMIT."
