#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/install-local-brotli4j.sh [--jni-only] BROTLI4J_DIR [VERSION] [PLATFORM]

Installs the brotli4j, service and native jars already built in a local brotli4j checkout into
the configured Maven local repository under VERSION (default: 1.24.0-LOCAL), so they can't be confused with the release of the
same version from Maven Central. PLATFORM defaults to the selected JVM architecture (Linux only).

Build the checkout first, on JDK 22+ so the jar contains the FFM classes, e.g.:
  mvn -pl brotli4j,service,natives/linux-x86_64 -am -DskipTests package
scripts/build-brotli4j.sh does both for a given commit.

--jni-only  The checkout has no FFM code (e.g. main before the FFM port): require that the jar has
            no FFM classes instead of requiring them.
EOF
}

JNI_ONLY=0
if [[ ${1:-} == --jni-only ]]; then
    JNI_ONLY=1
    shift
fi
readonly JNI_ONLY

if (( $# < 1 || $# > 3 )); then
    usage >&2
    exit 2
fi

NATIVE_PLATFORM=${3:-${NATIVE_PLATFORM:-}}
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

readonly SOURCE_DIR=$(cd -- "$1" && pwd)
readonly VERSION=${2:-1.24.0-LOCAL}
readonly PLATFORM=$NATIVE_PLATFORM
readonly GROUP_ID=com.aayushatharva.brotli4j

if [[ ! $VERSION =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: invalid Maven version: $VERSION" >&2
    exit 2
fi

# The single main jar in <dir>, ignoring sources/javadoc jars.
main_jar() {
    local dir=$1
    local pattern=$2
    local -a found
    mapfile -t found < <(find "$dir" -maxdepth 1 -name "$pattern" \
        ! -name '*-sources.jar' ! -name '*-javadoc.jar' 2>/dev/null)
    if (( ${#found[@]} != 1 )); then
        echo "Error: expected exactly one $pattern in $dir, found ${#found[@]}. Build the checkout first." >&2
        exit 1
    fi
    printf '%s\n' "${found[0]}"
}

readonly BROTLI4J_JAR=$(main_jar "$SOURCE_DIR/brotli4j/target" 'brotli4j-*.jar')
readonly SERVICE_JAR=$(main_jar "$SOURCE_DIR/service/target" 'service-*.jar')
readonly NATIVE_JAR=$(main_jar "$SOURCE_DIR/natives/$PLATFORM/target" "native-$PLATFORM-*.jar")

# Without these classes the "ffm" results would silently measure JNI; with them, a JNI-only baseline wouldn't be one.
if unzip -l "$BROTLI4J_JAR" | grep 'META-INF/versions/22/com/aayushatharva/brotli4j/encoder/FfmNativeFunctionCaller.class' >/dev/null; then
    if (( JNI_ONLY )); then
        echo "Error: $BROTLI4J_JAR has FFM classes, but --jni-only was given." >&2
        exit 1
    fi
elif (( ! JNI_ONLY )); then
    echo "Error: $BROTLI4J_JAR has no FFM classes; build it on JDK 22+ (or pass --jni-only)." >&2
    exit 1
fi

install_jar() {
    local artifact_id=$1
    local file=$2
    echo "Installing $file as $GROUP_ID:$artifact_id:$VERSION"
    mvn -q -B -ntp install:install-file -Dfile="$file" -DgroupId="$GROUP_ID" \
        -DartifactId="$artifact_id" -Dversion="$VERSION" -Dpackaging=jar -DgeneratePom=true
}

install_jar brotli4j "$BROTLI4J_JAR"
install_jar service "$SERVICE_JAR"
install_jar "native-$PLATFORM" "$NATIVE_JAR"

commit=$(git -C "$SOURCE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
branch=$(git -C "$SOURCE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
if ! git -C "$SOURCE_DIR" diff --quiet HEAD 2>/dev/null; then
    commit="$commit (with uncommitted changes)"
fi
echo "Installed $VERSION from $SOURCE_DIR, branch $branch, commit $commit."
