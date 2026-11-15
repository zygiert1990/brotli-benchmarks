#!/usr/bin/env bash

set -Eeuo pipefail

# Every benchmark class, in priority order: the cases most likely to show a JNI -> FFM difference first.
readonly -a BENCHMARKS=(
    EncoderLifecycleBenchmark
    DecoderLifecycleBenchmark
    EncoderOneShotBenchmark
    DecoderOneShotBenchmark
    EncoderStreamBufferSizeBenchmark
    EncoderStreamFlushBenchmark
    DecoderStreamBufferSizeBenchmark
    DecoderOutputCapBenchmark
    EncoderDictionaryBenchmark
    DecoderDictionaryBenchmark
)

usage() {
    cat <<'EOF'
Usage:
  scripts/run-all-benchmarks.sh [OPTIONS] [BENCHMARK...]

Runs scripts/run-benchmarks.sh for each selected benchmark (all of them by default), one after
another, against all targets (main, jni, ffm). The brotli4j commits are built once, before the
first benchmark, if not installed yet (BROTLI4J_REPO, MAIN_REF, FFM_REF; see run-benchmarks.sh).

Options:
  -n, --dry-run     Print the invocations without running them.
      --fail-fast   Stop at the first failing benchmark (default: run all, report at the end).
      --mode MODE   Passed to run-benchmarks.sh (ALL, GC, NATIVEMEM or FLAMEGRAPH).
  -h, --help        Show this help.
EOF
}

DRY_RUN=0
FAIL_FAST=0
declare -a MODE_OPTION=()
declare -a SELECTED=()
while (( $# > 0 )); do
    case $1 in
        -n|--dry-run) DRY_RUN=1; shift ;;
        --fail-fast) FAIL_FAST=1; shift ;;
        --mode)
            if (( $# < 2 )); then
                echo "Error: --mode requires a value." >&2
                exit 2
            fi
            MODE_OPTION=(--mode "$2")
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Error: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [[ ! " ${BENCHMARKS[*]} " == *" $1 "* ]]; then
                echo "Error: unknown benchmark: $1" >&2
                exit 2
            fi
            SELECTED+=("$1")
            shift
            ;;
    esac
done
if (( ${#SELECTED[@]} == 0 )); then
    SELECTED=("${BENCHMARKS[@]}")
fi

readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if (( ! DRY_RUN )); then
    # Once for all benchmarks; the exported versions make run-benchmarks.sh skip this step.
    source "$SCRIPT_DIR/common.sh"
    source "$SCRIPT_DIR/brotli4j-versions.sh"
    prepare_brotli4j 1 1 || exit 1
fi
declare -a SUCCEEDED=()
declare -a FAILED=()
start=$SECONDS

for benchmark in "${SELECTED[@]}"; do
    command=("$SCRIPT_DIR/run-benchmarks.sh" "${MODE_OPTION[@]}" "$benchmark")
    if (( DRY_RUN )); then
        printf '%q ' "${command[@]}"
        printf '\n'
        continue
    fi
    printf '\n===== %s =====\n' "$benchmark"
    if "${command[@]}"; then
        SUCCEEDED+=("$benchmark")
    else
        FAILED+=("$benchmark")
        if (( FAIL_FAST )); then
            break
        fi
    fi
done

if (( DRY_RUN )); then
    exit 0
fi

elapsed=$((SECONDS - start))
printf '\nSucceeded (%d): %s\n' "${#SUCCEEDED[@]}" "${SUCCEEDED[*]:-none}"
printf 'Failed (%d): %s\n' "${#FAILED[@]}" "${FAILED[*]:-none}"
printf 'Total time: %dh %dm %ds\n' $((elapsed / 3600)) $((elapsed % 3600 / 60)) $((elapsed % 60))
(( ${#FAILED[@]} == 0 ))
