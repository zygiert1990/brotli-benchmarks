#!/usr/bin/env bash
# Shared Linux prerequisites. Source this after handling --help.
# Bash 4.4+: earlier versions treat an empty "${array[@]}" as unbound under set -u.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )) || [[ $(uname -s) != Linux ]]; then
    echo "Error: these scripts require Linux and Bash 4.4+." >&2
    exit 1
fi
DEFAULT_JAVA=${DEFAULT_JAVA:-${JAVA_HOME:+$JAVA_HOME/bin/java}}
DEFAULT_JAVA=${DEFAULT_JAVA:-java}
DEFAULT_JAVA=$(command -v "$DEFAULT_JAVA") || { echo "Error: Java not found." >&2; exit 1; }
DEFAULT_JAVA=$(readlink -f "$DEFAULT_JAVA")
java_properties=$("$DEFAULT_JAVA" -XshowSettings:properties -version 2>&1)
java_version=$(awk -F' = ' '/^[[:space:]]*java.version = / {print $2}' <<< "$java_properties")
java_major=${java_version%%[.+-]*}
if [[ ! $java_major =~ ^[0-9]+$ ]] || (( java_major < 22 )); then
    echo "Error: JDK 22+ is required; selected Java is $java_version." >&2
    exit 1
fi
export JAVA_HOME=$(dirname "$(dirname "$DEFAULT_JAVA")")
export PATH="$JAVA_HOME/bin:$PATH"
java_arch=$(awk -F' = ' '/^[[:space:]]*os.arch = / {print $2}' <<< "$java_properties")
if [[ -z ${NATIVE_PLATFORM:-} ]]; then
    case $java_arch in
        amd64|x86_64) NATIVE_PLATFORM=linux-x86_64 ;;
        aarch64|arm64) NATIVE_PLATFORM=linux-aarch64 ;;
        arm|armv7l) NATIVE_PLATFORM=linux-armv7 ;;
        ppc64le|s390x|riscv64) NATIVE_PLATFORM=linux-$java_arch ;;
        *) echo "Error: unsupported JVM architecture: $java_arch" >&2; exit 1 ;;
    esac
fi
case $NATIVE_PLATFORM in
    linux-x86_64|linux-aarch64|linux-armv7|linux-ppc64le|linux-s390x|linux-riscv64) ;;
    *) echo "Error: unsupported Linux platform: $NATIVE_PLATFORM" >&2; exit 1 ;;
esac
