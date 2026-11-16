# Summary: ffm vs jni (execution time)

Latest run of each benchmark. Ratio < 1 means FFM is faster; verdicts use the JMH error margins.

| Benchmark | Cases | faster | same | slower | geometric mean ffm/jni | best | worst | Report |
|---|---|---|---|---|---|---|---|---|
| DecoderDictionaryBenchmark | 1 | 1 | 0 | 0 | 0.85 | 0.85 | 0.85 | [report](DecoderDictionaryBenchmark/20261116T142714-121393-26209/comparison.md) |
| DecoderLifecycleBenchmark | 4 | 4 | 0 | 0 | 0.54 | 0.52 | 0.56 | [report](DecoderLifecycleBenchmark/20261116T070429-50722-19217/comparison.md) |
| DecoderOneShotBenchmark | 6 | 5 | 1 | 0 | 0.86 | 0.58 | 1.00 | [report](DecoderOneShotBenchmark/20261116T091257-69616-26143/comparison.md) |
| DecoderOutputCapBenchmark | 4 | 4 | 0 | 0 | 0.75 | 0.42 | 0.99 | [report](DecoderOutputCapBenchmark/20261116T131702-108839-13748/comparison.md) |
| DecoderStreamBufferSizeBenchmark | 5 | 2 | 3 | 0 | 0.98 | 0.93 | 1.00 | [report](DecoderStreamBufferSizeBenchmark/20261116T121840-98094-9901/comparison.md) |
| EncoderDictionaryBenchmark | 2 | 1 | 1 | 0 | 0.98 | 0.95 | 1.01 | [report](EncoderDictionaryBenchmark/20261116T140347-117044-31247/comparison.md) |
| EncoderLifecycleBenchmark | 4 | 4 | 0 | 0 | 0.51 | 0.49 | 0.55 | [report](EncoderLifecycleBenchmark/20261116T061745-42376-7505/comparison.md) |
| EncoderOneShotBenchmark | 12 | 6 | 6 | 0 | 0.98 | 0.90 | 1.02 | [report](EncoderOneShotBenchmark/20261116T075113-58944-30705/comparison.md) |
| EncoderStreamBufferSizeBenchmark | 10 | 6 | 4 | 0 | 0.98 | 0.93 | 1.00 | [report](EncoderStreamBufferSizeBenchmark/20261116T100335-77318-16861/comparison.md) |
| EncoderStreamFlushBenchmark | 6 | 3 | 3 | 0 | 0.99 | 0.96 | 1.00 | [report](EncoderStreamFlushBenchmark/20261116T112755-90133-31232/comparison.md) |
