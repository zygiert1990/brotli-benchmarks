package org.zygiert;

import com.aayushatharva.brotli4j.decoder.Decoder;
import com.aayushatharva.brotli4j.decoder.DirectDecompress;
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

import java.io.IOException;
import java.util.concurrent.TimeUnit;

/**
 * {@code Decoder.decompress(byte[])}: what a user pays per message, including creating and destroying the
 * decoder. {@code inputSize} is the size before compression.
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class DecoderOneShotBenchmark {

    @Param({"256", "16384", "131072"})
    private int inputSize;

    @Param({"text", "random"})
    private String data;

    private byte[] compressed;

    @Setup(Level.Trial)
    public void setup() {
        Backend.verify();
        byte[] input = BenchmarkData.input(data, inputSize);
        compressed = BenchmarkData.compress(input, BenchmarkData.PRODUCTION_QUALITY);
        BenchmarkData.checkRoundTrip(compressed, input);
    }

    @Benchmark
    public DirectDecompress decompress() throws IOException {
        return Decoder.decompress(compressed);
    }
}
