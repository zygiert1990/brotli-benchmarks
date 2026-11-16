# Summary: ffm vs jni (execution time)

Latest run of each benchmark. Ratio < 1 means FFM is faster; verdicts use the JMH error margins.

| Benchmark | Cases | faster | same | slower | geometric mean ffm/jni | best | worst | Report |
|---|---|---|---|---|---|---|---|---|
| DecoderDictionaryBenchmark | 1 | 1 | 0 | 0 | 0.86 | 0.86 | 0.86 | [report](DecoderDictionaryBenchmark/20261115T155638-211797-28201/comparison.md) |
| DecoderLifecycleBenchmark | 4 | 4 | 0 | 0 | 0.61 | 0.57 | 0.66 | [report](DecoderLifecycleBenchmark/20261115T083348-121950-28126/comparison.md) |
| DecoderOneShotBenchmark | 6 | 4 | 2 | 0 | 0.85 | 0.57 | 1.00 | [report](DecoderOneShotBenchmark/20261115T104216-143346-27185/comparison.md) |
| DecoderOutputCapBenchmark | 4 | 3 | 1 | 0 | 0.75 | 0.42 | 0.99 | [report](DecoderOutputCapBenchmark/20261115T144624-195657-22559/comparison.md) |
| DecoderStreamBufferSizeBenchmark | 5 | 3 | 2 | 0 | 0.98 | 0.94 | 1.00 | [report](DecoderStreamBufferSizeBenchmark/20261115T134801-182786-27135/comparison.md) |
| EncoderDictionaryBenchmark | 2 | 1 | 1 | 0 | 0.98 | 0.95 | 1.01 | [report](EncoderDictionaryBenchmark/20261115T153310-206489-18715/comparison.md) |
| EncoderLifecycleBenchmark | 4 | 4 | 0 | 0 | 0.52 | 0.50 | 0.54 | [report](EncoderLifecycleBenchmark/20261115T074704-113742-4137/comparison.md) |
| EncoderOneShotBenchmark | 12 | 5 | 7 | 0 | 0.98 | 0.90 | 1.01 | [report](EncoderOneShotBenchmark/20261115T092031-130192-3994/comparison.md) |
| EncoderStreamBufferSizeBenchmark | 10 | 5 | 5 | 0 | 0.98 | 0.93 | 1.00 | [report](EncoderStreamBufferSizeBenchmark/20261115T113255-153985-31791/comparison.md) |
| EncoderStreamFlushBenchmark | 6 | 3 | 3 | 0 | 0.99 | 0.96 | 1.00 | [report](EncoderStreamFlushBenchmark/20261115T125716-171730-12002/comparison.md) |
