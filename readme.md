# brotli-benchmarks

JMH benchmarks comparing the JNI and FFM bindings of [Brotli4j](https://github.com/hyperxpro/Brotli4j).
Currently supported: **Linux only**, with Bash 4.4+, Maven, a JDK 22+ with an FFM linker, and standard Linux tools (`unzip`, `sha256sum`, `flock`, `timeout`, `lscpu`). Profiling additionally requires a compatible async-profiler installation.

Each benchmark runs against three targets on the same JDK. All of them are built locally from a
pinned commit with the same JDK and C toolchain, so differences come from the code, not from the build:

| Target | brotli4j | Backend |
|---|---|---|
| `main` | `1.24.0-MAIN`: `main` before the FFM port | JNI (the classes every user runs today) |
| `jni` | `1.24.0-LOCAL`: the FFM branch | JNI, through the JDK 22+ classes (`-Dbrotli4j.backend=jni`) |
| `ffm` | the same build as `jni` | FFM (`-Dbrotli4j.backend=ffm`) |

`main` vs `jni` shows what the JDK 22+ classes cost on their own; `jni` vs `ffm` compares the two
bindings in the same build.

## Benchmarks

| Benchmark | What it measures |
|---|---|
| `EncoderLifecycleBenchmark` | Creating and destroying an encoder wrapper; creating and closing an empty `BrotliOutputStream`. Each also on four threads. |
| `DecoderLifecycleBenchmark` | The same for the decoder and `BrotliInputStream`. |
| `EncoderOneShotBenchmark` | `Encoder.compress(byte[])` for 256 B, 16 KiB and 128 KiB of text and random data, quality 1 and 4. |
| `DecoderOneShotBenchmark` | `Decoder.decompress(byte[])` for the same inputs. |
| `EncoderStreamBufferSizeBenchmark` | Compressing the dataset through `BrotliOutputStream` with stream buffers from 64 B to 64 KiB. |
| `EncoderStreamFlushBenchmark` | Writing the dataset as 64 B - 4 KiB messages, flushing after each one vs. buffering. |
| `DecoderStreamBufferSizeBenchmark` | Decompressing the dataset through `BrotliInputStream` with buffers from 64 B to 64 KiB. |
| `DecoderOutputCapBenchmark` | Decompressing the dataset with the output per pull capped at 64 B - 64 KiB. |
| `EncoderDictionaryBenchmark` | Preparing and closing a 16 KiB dictionary; compressing a 1 KiB message with a prepared dictionary. |
| `DecoderDictionaryBenchmark` | Decompressing that message with the raw dictionary attached. |

Every benchmark checks its output outside the measured code (round trips, dictionary actually used) and
fails unless the expected backend is active (`-Dbenchmark.backend=base|jni|ffm`).

Test data is `src/main/resources/dataset-formatted.xml` (223634 bytes of XML records), the dataset of
zstd-benchmarks; random data comes from a fixed seed. Qualities: 1 (fast, shows per-call cost) and 4 (typical
for dynamic HTTP content). Dictionaries use quality 5, the lowest at which brotli uses them.

## Quick start

Build both versions from a Brotli4j clone and install them. Each commit is built in a temporary git
worktree, so the clone's checkout is left alone. Needs `cmake` and a C/C++ compiler on `PATH`:

```bash
# main before the FFM port (0a0ac32, head of main when these benchmarks were written)
scripts/build-brotli4j.sh --jni-only /path/to/Brotli4j 0a0ac32 1.24.0-MAIN
# the FFM branch
scripts/build-brotli4j.sh /path/to/Brotli4j add-support-for-ffm-api 1.24.0-LOCAL
```

`scripts/install-local-brotli4j.sh` installs an already built checkout instead.

Run one benchmark against all targets (GC results, native-memory summaries, CPU flamegraphs):

```bash
ASYNC_PROFILER_HOME=/path/to/async-profiler scripts/run-benchmarks.sh EncoderLifecycleBenchmark
```

Results go to `docs/<Benchmark>/<run-id>/<jdk>/<target>/`. Every invocation creates a new run,
including `--mode GC|NATIVEMEM|FLAMEGRAPH`; it never overwrites or merges earlier measurements.
Use GC mode without installing async-profiler, including on a fresh checkout:

```bash
scripts/run-benchmarks.sh --mode GC EncoderOneShotBenchmark jni ffm
```

Each run records the actual Java version, Linux/CPU/RAM details, arguments, dataset hash, and
per-target hashes of the benchmark JAR and Brotli dependency JARs. These generated records describe
the machine that produced the results; they are not required machine settings.

Run everything:

```bash
scripts/run-all-benchmarks.sh            # or --dry-run to list the invocations
```

Check the scripts quickly with short runs (the results are meaningless):

```bash
EXTRA_JMH_ARGS="-f 1 -wi 0 -i 1 -r 200ms" scripts/run-benchmarks.sh DecoderOutputCapBenchmark
```

Run a single benchmark by hand; `benchmark.backend` must match what is active:

```bash
mvn clean package -Dbrotli4j.version=1.24.0-LOCAL # native platform detected by Maven
java -jar target/benchmarks.jar EncoderLifecycleBenchmark -prof gc \
  -jvmArgsPrepend "-Dbrotli4j.backend=ffm -Dbenchmark.backend=ffm"
```

## Settings

All benchmarks use 3 forks, 3 × 3 s warmup and 5 × 5 s measurement, with a fixed, pre-touched 2 GB G1
heap and `--enable-native-access=ALL-UNNAMED`. Native-memory profiles use 1 fork, 3 + 3 iterations.

Java is selected from `DEFAULT_JAVA`, then `JAVA_HOME/bin/java`, then `java` on `PATH`.
The scripts also use that JDK for Maven. Maven's configured local repository is respected.
Linux native artifacts are selected from the JVM architecture; override with `NATIVE_PLATFORM`
for scripts or `-Dnative.platform=linux-aarch64` for manual Maven commands.
Supported artifact names: `linux-x86_64`, `linux-aarch64`, `linux-armv7`, `linux-ppc64le`,
`linux-s390x`, `linux-riscv64`. FFM and async-profiler availability depend on the selected JVM/platform.

| Variable | Default / meaning |
|---|---|
| `DEFAULT_JAVA` | Java selection described above; JDK 22+ required |
| `ASYNC_PROFILER_HOME` | Set to your async-profiler distribution directory for profiling |
| `ASYNC_PROFILER_LIB` | Overrides the profiler library path |
| `NATIVE_PLATFORM` | Detected from the selected JVM architecture |
| `MAIN_VERSION` / `LOCAL_VERSION` | `1.24.0-MAIN` / `1.24.0-LOCAL` |
| `RESULT_ROOT` | Repository `docs` directory |
| `RUN_ID` | Unique UTC timestamp/process/random identifier; existing run directories are rejected |
| `INHIBIT_SLEEP` | `auto`: use GNOME inhibition when usable; `required`: fail if unavailable; `off`: disable |
| `EXTRA_JMH_ARGS` | Additional whitespace-separated JMH arguments; no shell quoting within the value |

For local desktop measurements, use `INHIBIT_SLEEP=required` to guarantee idle/suspend inhibition.
Auto mode probes the GNOME session before starting and works over SSH without a desktop session.
Benchmark failures are never retried without inhibition. Only one runner may build in a checkout
at a time. Decoder output buffers are thread-local, including when overriding JMH's thread count.
