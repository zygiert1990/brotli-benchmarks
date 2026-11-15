#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/run-benchmarks.sh [--mode MODE] BENCHMARK [TARGET...]

Runs one benchmark class against these targets (all of them by default):
  main     MAIN_REF (default 0a0ac32): brotli4j main before the FFM port, JNI only
  jni      FFM_REF (default add-support-for-ffm-api) with -Dbrotli4j.backend=jni
  ffm      FFM_REF with -Dbrotli4j.backend=ffm

Commits are taken from the brotli4j clone in BROTLI4J_REPO and built first if not installed yet
(see scripts/brotli4j-versions.sh). MAIN_VERSION / LOCAL_VERSION select installed versions instead.

Example:
  scripts/run-benchmarks.sh EncoderLifecycleBenchmark
  scripts/run-benchmarks.sh --mode GC EncoderOneShotBenchmark jni ffm

Modes:
  ALL         Collect all measurements in a new run directory (default).
  GC          Collect only results.txt files.
  NATIVEMEM   Collect only native-memory summaries and their JMH result files.
  FLAMEGRAPH  Collect only CPU flamegraphs.
EOF
}

MODE=ALL
while (( $# > 0 )); do
    case $1 in
        --mode)
            if (( $# < 2 )); then
                echo "Error: --mode requires a value." >&2
                usage >&2
                exit 2
            fi
            MODE=${2^^}
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *) break ;;
    esac
done

if [[ ! $MODE =~ ^(ALL|GC|NATIVEMEM|FLAMEGRAPH)$ ]]; then
    echo "Error: mode must be ALL, GC, NATIVEMEM, or FLAMEGRAPH: $MODE" >&2
    exit 2
fi
readonly MODE

if (( $# == 0 )); then
    usage
    exit 2
fi

BENCHMARK=$1
shift
if [[ ! $BENCHMARK =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Error: benchmark must be a simple Java class name." >&2
    exit 2
fi
readonly BENCHMARK

readonly PROJECT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec 9>"$PROJECT_DIR/.benchmark.lock"
flock -n 9 || { echo "Error: another benchmark runner is using this checkout." >&2; exit 1; }
readonly BENCHMARK_JAR="$PROJECT_DIR/target/benchmarks.jar"
source "$PROJECT_DIR/scripts/common.sh"
readonly RESULT_ROOT=${RESULT_ROOT:-$PROJECT_DIR/docs}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%S)-$$-$RANDOM}
if [[ ! $RUN_ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "Error: invalid RUN_ID." >&2; exit 1
fi
readonly RESULT_DIR="$RESULT_ROOT/$BENCHMARK/$RUN_ID"
readonly ASYNC_PROFILER_LIB=${ASYNC_PROFILER_LIB:-${ASYNC_PROFILER_HOME:+$ASYNC_PROFILER_HOME/lib/libasyncProfiler.so}}
# Appended to every JMH run, e.g. EXTRA_JMH_ARGS="-f 1 -wi 0 -i 1 -r 100ms" to check the script quickly.
read -r -a EXTRA_JMH_ARGS <<< "${EXTRA_JMH_ARGS:-}"
readonly -a EXTRA_JMH_ARGS

# Target name -> the JVM options selecting/asserting its backend.
declare -A TARGET_JVM_ARGS=(
    [main]="-Dbenchmark.backend=base"
    [jni]="-Dbrotli4j.backend=jni -Dbenchmark.backend=jni"
    [ffm]="-Dbrotli4j.backend=ffm -Dbenchmark.backend=ffm"
)
declare -a TARGETS=()
if (( $# == 0 )); then
    TARGETS=(main jni ffm)
else
    declare -A seen_targets=()
    for target in "$@"; do
        if [[ -z ${TARGET_JVM_ARGS[$target]+x} ]]; then
            echo "Error: unknown target: $target (expected main, jni or ffm)" >&2
            exit 2
        fi
        if [[ -n ${seen_targets[$target]+x} ]]; then
            echo "Error: duplicate target: $target" >&2
            exit 2
        fi
        seen_targets[$target]=1
        TARGETS+=("$target")
    done
fi
readonly -a TARGETS

# Build the brotli4j commits the selected targets need, unless already installed.
source "$PROJECT_DIR/scripts/brotli4j-versions.sh"
need_main=0
need_ffm=0
for target in "${TARGETS[@]}"; do
    if [[ $target == main ]]; then need_main=1; else need_ffm=1; fi
done
prepare_brotli4j "$need_main" "$need_ffm" || exit 1
readonly MAIN_VERSION=${MAIN_VERSION:-} LOCAL_VERSION=${LOCAL_VERSION:-}
declare -A TARGET_VERSION=([main]=$MAIN_VERSION [jni]=$LOCAL_VERSION [ffm]=$LOCAL_VERSION)

# Profiled runs (native memory, flamegraph) cover one parameter sweep or a list of methods per benchmark.
# PROFILE_PARAMETER=method: PROFILE_VALUES are method names. Otherwise each value of PROFILE_PARAMETER is
# profiled with the other parameters fixed by PROFILE_FIXED, for the methods matching PROFILE_METHOD.
PROFILE_PARAMETER=
PROFILE_PREFIX=
PROFILE_VALUES=(default)
PROFILE_METHOD=
PROFILE_FIXED=()
case $BENCHMARK in
    EncoderLifecycleBenchmark)
        PROFILE_PARAMETER=method
        PROFILE_PREFIX=method-
        PROFILE_VALUES=(createAndDestroyWrapper createAndDestroyWrapperOnFourThreads
            createAndCloseEmptyStream createAndCloseEmptyStreamOnFourThreads)
        ;;
    DecoderLifecycleBenchmark)
        PROFILE_PARAMETER=method
        PROFILE_PREFIX=method-
        PROFILE_VALUES=(createAndDestroyWrapper createAndDestroyWrapperOnFourThreads
            createAndCloseStream createAndCloseStreamOnFourThreads)
        ;;
    EncoderOneShotBenchmark)
        PROFILE_PARAMETER=inputSize
        PROFILE_PREFIX=input-
        PROFILE_VALUES=(256 16384 131072)
        PROFILE_FIXED=(-p data=text -p quality=1)
        ;;
    DecoderOneShotBenchmark)
        PROFILE_PARAMETER=inputSize
        PROFILE_PREFIX=input-
        PROFILE_VALUES=(256 16384 131072)
        PROFILE_FIXED=(-p data=text)
        ;;
    EncoderStreamBufferSizeBenchmark)
        PROFILE_PARAMETER=bufferSize
        PROFILE_PREFIX=buffer-
        PROFILE_VALUES=(64 512 4096 16384 65536)
        PROFILE_FIXED=(-p quality=1)
        ;;
    EncoderStreamFlushBenchmark)
        PROFILE_PARAMETER=messageSize
        PROFILE_PREFIX=message-
        PROFILE_VALUES=(64 512 4096)
        PROFILE_METHOD=flushEveryMessage
        ;;
    DecoderStreamBufferSizeBenchmark)
        PROFILE_PARAMETER=bufferSize
        PROFILE_PREFIX=buffer-
        PROFILE_VALUES=(64 512 4096 16384 65536)
        ;;
    DecoderOutputCapBenchmark)
        PROFILE_PARAMETER=maxOutputChunkSize
        PROFILE_PREFIX=cap-
        PROFILE_VALUES=(64 512 4096 65536)
        ;;
    EncoderDictionaryBenchmark)
        PROFILE_PARAMETER=method
        PROFILE_PREFIX=method-
        PROFILE_VALUES=(prepareAndCloseDictionary compressMessageWithDictionary)
        ;;
    DecoderDictionaryBenchmark)
        ;;
    *)
        echo "Error: no profile configuration for $BENCHMARK; add it to the case statement." >&2
        exit 2
        ;;
esac
readonly PROFILE_PARAMETER PROFILE_PREFIX PROFILE_METHOD
readonly -a PROFILE_VALUES PROFILE_FIXED

TASKS_PER_TARGET=0
[[ $MODE == ALL || $MODE == GC ]] && TASKS_PER_TARGET=$((TASKS_PER_TARGET + 1))
[[ $MODE == ALL || $MODE == NATIVEMEM ]] && TASKS_PER_TARGET=$((TASKS_PER_TARGET + ${#PROFILE_VALUES[@]}))
[[ $MODE == ALL || $MODE == FLAMEGRAPH ]] && TASKS_PER_TARGET=$((TASKS_PER_TARGET + ${#PROFILE_VALUES[@]}))
readonly TASKS_PER_TARGET
readonly TOTAL_STEPS=$(( TASKS_PER_TARGET * ${#TARGETS[@]} ))
CURRENT_STEP=0

announce() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf '\n[%s] [%d/%d] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$CURRENT_STEP" "$TOTAL_STEPS" "$1"
}

completed() {
    printf '[%s] Completed: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Probe inhibition once, before running any benchmark. Never rerun a failed benchmark.
INHIBIT_SLEEP=${INHIBIT_SLEEP:-auto}
case $INHIBIT_SLEEP in auto|required|off) ;; *) echo "Invalid INHIBIT_SLEEP" >&2; exit 1 ;; esac
INHIBITOR=()
if [[ $INHIBIT_SLEEP != off ]]; then
    if command -v gnome-session-inhibit >/dev/null 2>&1 &&
       timeout 10 gnome-session-inhibit --inhibit idle:suspend --reason "Running JMH" true >/dev/null 2>&1; then
        INHIBITOR=(gnome-session-inhibit --inhibit idle:suspend --reason "Running JMH")
    elif [[ $INHIBIT_SLEEP == required ]]; then
        echo "Error: a usable GNOME session inhibitor is required." >&2; exit 1
    else
        echo "GNOME sleep inhibition unavailable; continuing without inhibition." >&2
    fi
fi
# 9>&-: benchmark processes don't inherit the lock, so one that outlives this script can't keep holding it.
run_inhibited() { "${INHIBITOR[@]}" "$@" 9>&-; }

for command in mvn "$DEFAULT_JAVA"; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command is unavailable: $command" >&2
        exit 1
    fi
done
if [[ $MODE != GC && -z $ASYNC_PROFILER_LIB ]]; then
    echo "Error: mode $MODE needs async-profiler; set ASYNC_PROFILER_HOME (or ASYNC_PROFILER_LIB), or use --mode GC." >&2
    exit 1
fi
if [[ $MODE != GC && ! -f $ASYNC_PROFILER_LIB ]]; then
    echo "Error: async-profiler library is unavailable: $ASYNC_PROFILER_LIB" >&2
    exit 1
fi
if [[ ! -f $PROJECT_DIR/src/main/java/org/zygiert/$BENCHMARK.java ]]; then
    echo "Error: benchmark source does not exist: src/main/java/org/zygiert/$BENCHMARK.java" >&2
    exit 1
fi
readonly JAVA_DIR=jdk-${java_version//./-}

BUILT_VERSION=
build() {
    local version=$1
    if [[ $BUILT_VERSION == "$version" ]]; then
        return
    fi
    echo "Building benchmarks.jar against brotli4j $version"
    (cd -- "$PROJECT_DIR" && mvn -q -B -ntp clean package -Dbrotli4j.version="$version" -Dnative.platform="$NATIVE_PLATFORM"
        mvn -q -B -ntp dependency:copy-dependencies -Dbrotli4j.version="$version" \
            -Dnative.platform="$NATIVE_PLATFORM" -DincludeGroupIds=com.aayushatharva.brotli4j \
            -DoutputDirectory=target/brotli-artifacts) 9>&-
    BUILT_VERSION=$version
}

run_target() {
    local target=$1
    local destination="$RESULT_DIR/$JAVA_DIR/$target"
    local -a jvm_args=(-jvmArgsPrepend "${TARGET_JVM_ARGS[$target]}")
    local -a common=(-foe true "${jvm_args[@]}")
    local -a extra=("${EXTRA_JMH_ARGS[@]}")
    # One fork, shorter iterations; EXTRA_JMH_ARGS replaces them (JMH rejects repeated options).
    local -a nativemem_runs=(-f 1 -wi 3 -i 3)
    if (( ${#extra[@]} > 0 )); then
        nativemem_runs=("${extra[@]}")
    fi
    local profile_value
    local -a profile_option
    local profile_benchmark

    mkdir -p -- "$destination"
    {
        printf 'Target: %s\nVersion: %s\nJVM options: %s\n' "$target" "${TARGET_VERSION[$target]}" "${TARGET_JVM_ARGS[$target]}"
        sha256sum "$BENCHMARK_JAR" "$PROJECT_DIR"/target/brotli-artifacts/*.jar | sed "s|$PROJECT_DIR/||g"
    } > "$destination/artifacts.txt"

    if [[ $MODE == ALL || $MODE == GC ]]; then
        rm -f -- "$destination/results.txt"
        announce "$target on $JAVA_DIR: GC benchmark"
        run_inhibited "$DEFAULT_JAVA" -jar "$BENCHMARK_JAR" "$BENCHMARK" -prof gc "${common[@]}" \
            "${extra[@]}" -rf text -rff "$destination/results.txt"
        completed "$target on $JAVA_DIR: GC benchmark"
    fi

    for kind in NATIVEMEM FLAMEGRAPH; do
        if [[ $MODE != ALL && $MODE != "$kind" ]]; then
            continue
        fi
        for profile_value in "${PROFILE_VALUES[@]}"; do
            profile_option=()
            if [[ $PROFILE_PARAMETER == method ]]; then
                profile_benchmark="$BENCHMARK[.]$profile_value\$"
            else
                profile_benchmark="$BENCHMARK[.]${PROFILE_METHOD:-[^.]*}\$"
                profile_option=("${PROFILE_FIXED[@]}")
                if [[ -n $PROFILE_PARAMETER ]]; then
                    profile_option+=(-p "$PROFILE_PARAMETER=$profile_value")
                fi
            fi
            local case_destination="$destination/$PROFILE_PREFIX$profile_value"
            local profiler_dir="$PROJECT_DIR/target/async-profiler-$target-$profile_value"
            local label="$target on $JAVA_DIR: ${kind,,} profile (${PROFILE_PARAMETER:-case} $profile_value)"
            rm -rf -- "$profiler_dir"
            mkdir -p -- "$case_destination"

            announce "$label"
            if [[ $kind == NATIVEMEM ]]; then
                local raw_output
                raw_output=$(mktemp)
                rm -f -- "$case_destination/summary-nativemem.txt" "$case_destination/results-nativemem.json"
                run_inhibited "$DEFAULT_JAVA" -jar "$BENCHMARK_JAR" "$profile_benchmark" "${profile_option[@]}" \
                    -prof "async:libPath=$ASYNC_PROFILER_LIB;event=nativemem;output=text;dir=$profiler_dir" \
                    "${nativemem_runs[@]}" "${common[@]}" -rf json -rff "$case_destination/results-nativemem.json" \
                    > "$raw_output" 2>&1 || { cat -- "$raw_output" >&2; exit 1; }
                # The allocation summary JMH prints after the run: header, separator and rows.
                awk '
                /^[[:space:]]+bytes[[:space:]]+percent[[:space:]]+samples[[:space:]]+top[[:space:]]*$/ {
                    capture = 1; print; next
                }
                capture && /^[[:space:]]*-+[[:space:]]+-+[[:space:]]+-+[[:space:]]+-+[[:space:]]*$/ { print; next }
                capture && /^[[:space:]]*[0-9]+[[:space:]]+[0-9.]+%[[:space:]]+[0-9]+[[:space:]]+/ { print; next }
                capture { exit }
                ' "$raw_output" > "$case_destination/summary-nativemem.txt"
                rm -f -- "$raw_output"
                if [[ ! -s $case_destination/summary-nativemem.txt || ! -s $case_destination/results-nativemem.json ]]; then
                    echo "Error: native-memory results missing for ${PROFILE_PARAMETER:-case} $profile_value." >&2
                    exit 1
                fi
            else
                local -a flamegraphs
                rm -f -- "$case_destination/flame-cpu-forward.html"
                run_inhibited "$DEFAULT_JAVA" -jar "$BENCHMARK_JAR" "$profile_benchmark" "${profile_option[@]}" \
                    -prof "async:libPath=$ASYNC_PROFILER_LIB;event=cpu;output=flamegraph;direction=forward;dir=$profiler_dir" \
                    "${common[@]}" "${extra[@]}"
                mapfile -t flamegraphs < <(find "$profiler_dir" -type f -name '*.html' -print)
                if (( ${#flamegraphs[@]} != 1 )); then
                    echo "Error: expected one flamegraph for ${PROFILE_PARAMETER:-case} $profile_value;" \
                        "found ${#flamegraphs[@]}." >&2
                    exit 1
                fi
                cp -- "${flamegraphs[0]}" "$case_destination/flame-cpu-forward.html"
            fi
            rm -rf -- "$profiler_dir"
            completed "$label"
        done
    done
}

# Reserve a new directory even for GC-only runs; existing results are never overwritten.
mkdir -p -- "$RESULT_ROOT/$BENCHMARK"
if ! mkdir -- "$RESULT_DIR"; then
    echo "Error: run already exists; select a new RUN_ID." >&2; exit 1
fi
{
    printf 'Benchmark: %s\nMode: %s\nTargets: %s\nPlatform: %s\n' "$BENCHMARK" "$MODE" "${TARGETS[*]}" "$NATIVE_PLATFORM"
    printf 'Extra JMH arguments: %s\nInhibition: %s\n' "${EXTRA_JMH_ARGS[*]}" "${INHIBITOR[*]:-off}"
    printf 'main: %s (commit %s)\njni/ffm: %s (commit %s)\n' "${MAIN_VERSION:-unused}" "${MAIN_COMMIT:-n/a}" \
        "${LOCAL_VERSION:-unused}" "${FFM_COMMIT:-n/a}"
    "$DEFAULT_JAVA" -version 2>&1
    uname -srm
    LC_ALL=C lscpu
    awk '/MemTotal/ {print}' /proc/meminfo
    sha256sum "$PROJECT_DIR/src/main/resources/dataset-formatted.xml" | sed "s|$PROJECT_DIR/||g"
    if [[ $MODE != GC ]]; then sha256sum "$ASYNC_PROFILER_LIB"; fi
} > "$RESULT_DIR/metadata.txt"
echo "Results: $RESULT_DIR"

for target in "${TARGETS[@]}"; do
    build "${TARGET_VERSION[$target]}"
    run_target "$target"
done
