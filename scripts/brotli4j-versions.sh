#!/usr/bin/env bash
# Resolves the brotli4j commits to benchmark and builds those not installed yet. Source after common.sh.
#
#   BROTLI4J_REPO  brotli4j clone to build from (required unless both versions below are given)
#   MAIN_REF       baseline: main before the FFM port (default 0a0ac32), built with --jni-only
#   FFM_REF        the FFM branch (default add-support-for-ffm-api)
#   MAIN_VERSION / LOCAL_VERSION  use an already installed version instead of building that ref
#
# Each build is installed as <pom version>-MAIN-<commit> or <pom version>-FFM-<commit>, so a new commit on a
# branch is built automatically and an outdated build can't be measured by mistake. Uncommitted changes in
# BROTLI4J_REPO are not built.

BROTLI4J_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# prepare_brotli4j NEED_MAIN NEED_FFM: sets and exports MAIN_VERSION / LOCAL_VERSION (and MAIN_COMMIT /
# FFM_COMMIT when built from a ref) for the targets that need them.
prepare_brotli4j() {
    local need_main=$1
    local need_ffm=$2
    if (( need_main )) && [[ -z ${MAIN_VERSION:-} ]]; then
        MAIN_COMMIT=$(brotli4j_commit "${MAIN_REF:-0a0ac32}") || return 1
        MAIN_VERSION=$(brotli4j_version "$MAIN_COMMIT" MAIN) || return 1
        brotli4j_ensure_built "$MAIN_COMMIT" "$MAIN_VERSION" --jni-only || return 1
    fi
    if (( need_ffm )) && [[ -z ${LOCAL_VERSION:-} ]]; then
        FFM_COMMIT=$(brotli4j_commit "${FFM_REF:-add-support-for-ffm-api}") || return 1
        LOCAL_VERSION=$(brotli4j_version "$FFM_COMMIT" FFM) || return 1
        brotli4j_ensure_built "$FFM_COMMIT" "$LOCAL_VERSION" || return 1
    fi
    export MAIN_VERSION LOCAL_VERSION MAIN_COMMIT FFM_COMMIT
}

brotli4j_repo() {
    if [[ -z ${BROTLI4J_REPO:-} ]]; then
        echo "Error: set BROTLI4J_REPO to a brotli4j clone (or MAIN_VERSION / LOCAL_VERSION to installed versions)." >&2
        return 1
    fi
    if ! git -C "$BROTLI4J_REPO" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: BROTLI4J_REPO is not a git repository: $BROTLI4J_REPO" >&2
        return 1
    fi
    (cd -- "$BROTLI4J_REPO" && pwd)
}

brotli4j_commit() {
    local repo
    repo=$(brotli4j_repo) || return 1
    git -C "$repo" rev-parse --verify --quiet "$1^{commit}" || {
        echo "Error: $1 is not a commit in $repo." >&2
        return 1
    }
}

# <version of brotli4j-parent at the commit>-<KIND>-<short commit>, e.g. 1.24.0-FFM-504f9821ab
brotli4j_version() {
    local repo
    local pom_version
    repo=$(brotli4j_repo) || return 1
    pom_version=$(git -C "$repo" show "$1:pom.xml" | awk '
        /<artifactId>brotli4j-parent<\/artifactId>/ { parent = 1; next }
        parent && /<version>/ { gsub(/.*<version>|<\/version>.*/, ""); print; exit }')
    if [[ ! $pom_version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
        echo "Error: cannot read the brotli4j version at $1." >&2
        return 1
    fi
    printf '%s-%s-%s\n' "$pom_version" "$2" "$(git -C "$repo" rev-parse --short=10 "$1")"
}

brotli4j_local_repository() {
    if [[ -z ${BROTLI4J_M2:-} ]]; then
        BROTLI4J_M2=$(mvn -q -B -ntp help:evaluate -Dexpression=settings.localRepository -DforceStdout 9>&-) || {
            echo "Error: cannot read the Maven local repository location." >&2
            return 1
        }
    fi
    printf '%s\n' "$BROTLI4J_M2"
}

# brotli4j_ensure_built COMMIT VERSION [--jni-only]: builds and installs unless all three jars are installed.
brotli4j_ensure_built() {
    local commit=$1
    local version=$2
    local m2
    local artifact
    local missing=0
    m2=$(brotli4j_local_repository) || return 1
    for artifact in brotli4j service "native-$NATIVE_PLATFORM"; do
        if [[ ! -f $m2/com/aayushatharva/brotli4j/$artifact/$version/$artifact-$version.jar ]]; then
            missing=1
        fi
    done
    if (( ! missing )); then
        echo "Using installed brotli4j $version."
        return 0
    fi
    "$BROTLI4J_SCRIPT_DIR/build-brotli4j.sh" ${3:+"$3"} "$(brotli4j_repo)" "$commit" "$version" 9>&-
}
