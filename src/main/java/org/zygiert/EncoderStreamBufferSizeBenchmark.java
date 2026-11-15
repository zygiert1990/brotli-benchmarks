package org.zygiert;

import com.aayushatharva.brotli4j.encoder.BrotliOutputStream;
import com.aayushatharva.brotli4j.encoder.Encoder;
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

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.concurrent.TimeUnit;

/**
 * Compressing the dataset through {@link BrotliOutputStream}. The stream collects writes in its input buffer
 * and calls native code once the buffer is full, so {@code bufferSize} sets how often native code is called.
 * The dataset is written in one call: the size of user writes doesn't change the number of native calls.
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class EncoderStreamBufferSizeBenchmark {

    @Param({"64", "512", "4096", "16384", "65536"})
    private int bufferSize;

    @Param({"1", "4"})
    private int quality;

    private byte[] dataset;
    private Encoder.Parameters parameters;

    @Setup(Level.Trial)
    public void setup() throws IOException {
        Backend.verify();
        dataset = BenchmarkData.dataset();
        parameters = Encoder.Parameters.create(quality);
        ByteArrayOutputStream compressed = new ByteArrayOutputStream();
        compress(compressed);
        BenchmarkData.checkRoundTrip(compressed.toByteArray(), dataset);
    }

    @Benchmark
    public void compressDataset() throws IOException {
        compress(OutputStream.nullOutputStream());
    }

    private void compress(OutputStream destination) throws IOException {
        try (BrotliOutputStream out = new BrotliOutputStream(destination, parameters, bufferSize)) {
            out.write(dataset);
        }
    }
}
