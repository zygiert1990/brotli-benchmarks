# EncoderLifecycleBenchmark — jdk-25-0-5

- `main`: 1.24.0-MAIN-0a0ac32db6 (commit 0a0ac32db68a9c2630a53f866c5eab280f1e427b)
- `jni` / `ffm`: 1.24.0-FFM-504f982a60 (commit 504f982a6043e8b91525880cea886ebcae530e69) (`-Dbrotli4j.backend=jni` / `ffm`)
- Java: OpenJDK Runtime Environment Temurin-25.0.5+8 (build 25.0.5+8-LTS); host: Linux 6.8.0-138-generic x86_64, Intel(R) Core(TM) i5-8500 CPU @ 3.00GHz, 16 GB
- Run: `20261115T074704-113742-4137`, mode ALL, extra JMH arguments: `none`

Bars are relative to the worst result of their row. Labels show the value and the change versus `main`; negative is better. ★ marks the best result of a row.

![comparison-performance.svg](comparison-performance.svg)
![comparison-heap.svg](comparison-heap.svg)
![comparison-native.svg](comparison-native.svg)

Native allocation is estimated from async-profiler's `nativemem` samples during the measurement iterations. It doesn't see `ffm`'s own `malloc` downcall (32 bytes plus the input buffer per wrapper): FFM calls libc's `malloc` directly, past the profiler's hook. So `ffm` values cover brotli's allocations only, and lower `ffm` values don't mean FFM allocates less.

## Execution time

`faster` / `slower`: the difference exceeds both JMH error margins (99.9%); otherwise `same`.

| Case | main | jni | ffm | ffm vs jni | ffm vs main |
|---|---|---|---|---|---|
| createAndCloseEmptyStream | 0.866 ± 0.021 us/op | 0.872 ± 0.039 us/op | 0.440 ± 0.014 us/op | faster (-49.5%) | faster (-49.2%) |
| createAndCloseEmptyStreamOnFourThreads | 0.878 ± 0.017 us/op | 0.885 ± 0.002 us/op | 0.459 ± 0.022 us/op | faster (-48.1%) | faster (-47.7%) |
| createAndDestroyWrapper | 0.434 ± 0.001 us/op | 0.429 ± 0.008 us/op | 0.230 ± 0.007 us/op | faster (-46.4%) | faster (-47.0%) |
| createAndDestroyWrapperOnFourThreads | 0.416 ± 0.003 us/op | 0.412 ± 0.005 us/op | 0.222 ± 0.002 us/op | faster (-46.1%) | faster (-46.6%) |
