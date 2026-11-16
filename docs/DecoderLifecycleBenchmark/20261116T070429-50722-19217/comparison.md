# DecoderLifecycleBenchmark — jdk-25-0-5

- `main`: 1.24.0-MAIN-0a0ac32db6 (commit 0a0ac32db68a9c2630a53f866c5eab280f1e427b)
- `jni` / `ffm`: 1.24.0-FFM-8da156e83e (commit 8da156e83e7045083189f9eed6833e53420a5bd7) (`-Dbrotli4j.backend=jni` / `ffm`)
- Java: OpenJDK Runtime Environment Temurin-25.0.5+8 (build 25.0.5+8-LTS); host: Linux 6.8.0-138-generic x86_64, Intel(R) Core(TM) i5-8500 CPU @ 3.00GHz, 16 GB
- Run: `20261116T070429-50722-19217`, mode ALL, extra JMH arguments: `none`

Bars are relative to the worst result of their row. Labels show the value and the change versus `main`; negative is better. ★ marks the best result of a row.

![comparison-performance.svg](comparison-performance.svg)
![comparison-heap.svg](comparison-heap.svg)
![comparison-native.svg](comparison-native.svg)

Native allocation is estimated from async-profiler's `nativemem` samples during the measurement iterations. The profiler doesn't see `ffm`'s own `malloc` downcall: FFM calls libc's `malloc` directly, past the profiler's hook. Its size is exact (the out-parameter cells plus the input buffer per wrapper), so `ffm` values are the measured value plus that count, labelled `measured + FFM malloc`.

## Execution time

`faster` / `slower`: the difference exceeds both JMH error margins (99.9%); otherwise `same`.

| Case | main | jni | ffm | ffm vs jni | ffm vs main |
|---|---|---|---|---|---|
| createAndCloseStream | 0.546 ± 0.008 us/op | 0.522 ± 0.011 us/op | 0.290 ± 0.009 us/op | faster (-44.4%) | faster (-46.9%) |
| createAndCloseStreamOnFourThreads | 0.524 ± 0.008 us/op | 0.523 ± 0.009 us/op | 0.275 ± 0.005 us/op | faster (-47.4%) | faster (-47.5%) |
| createAndDestroyWrapper | 0.489 ± 0.002 us/op | 0.482 ± 0.010 us/op | 0.271 ± 0.006 us/op | faster (-43.8%) | faster (-44.6%) |
| createAndDestroyWrapperOnFourThreads | 0.489 ± 0.003 us/op | 0.475 ± 0.002 us/op | 0.249 ± 0.002 us/op | faster (-47.6%) | faster (-49.1%) |
