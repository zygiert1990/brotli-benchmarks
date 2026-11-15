package org.zygiert;

import com.aayushatharva.brotli4j.decoder.BrotliInputStream;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Warmup;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

/**
 * Decompressing the dataset with the output of each native pull capped at {@code maxOutputChunkSize} bytes.
 * Small caps mean many pulls for the same input, independent of the input buffer (the default, 16 KiB).
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Thread)
public class DecoderOutputCapBenchmark {

    private static final int BUFFER_SIZE = 16384;

    @Param({"64", "512", "4096", "65536"})
    private int maxOutputChunkSize;

    private byte[] compressed;
    private final byte[] readBuffer = new byte[8192];

    @Setup(Level.Trial)
    public void setup() throws IOException {
        Backend.verify();
        byte[] dataset = BenchmarkData.dataset();
        compressed = BenchmarkData.compress(dataset, BenchmarkData.PRODUCTION_QUALITY);
        BenchmarkData.checkStreamRoundTrip(open(), dataset);
    }

    @Benchmark
    public long decompressDataset() throws IOException {
        return BenchmarkData.drain(open(), readBuffer);
    }

    private BrotliInputStream open() throws IOException {
        return new BrotliInputStream(new ByteArrayInputStream(compressed), BUFFER_SIZE, maxOutputChunkSize);
    }
}
