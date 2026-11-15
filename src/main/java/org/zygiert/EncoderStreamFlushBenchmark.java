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
 * Writing the dataset as messages of {@code messageSize} bytes, as a server streaming a response does.
 * {@code flushEveryMessage} flushes after each message, so native code runs per message and emits little
 * output per call; {@code writeMessagesBuffered} leaves it to the stream buffer (the default, 16 KiB).
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class EncoderStreamFlushBenchmark {

    @Param({"64", "512", "4096"})
    private int messageSize;

    private byte[] dataset;
    private Encoder.Parameters parameters;

    @Setup(Level.Trial)
    public void setup() throws IOException {
        Backend.verify();
        dataset = BenchmarkData.dataset();
        parameters = Encoder.Parameters.create(BenchmarkData.PRODUCTION_QUALITY);
        for (boolean flush : new boolean[]{true, false}) {
            ByteArrayOutputStream compressed = new ByteArrayOutputStream();
            write(compressed, flush);
            BenchmarkData.checkRoundTrip(compressed.toByteArray(), dataset);
        }
    }

    @Benchmark
    public void flushEveryMessage() throws IOException {
        write(OutputStream.nullOutputStream(), true);
    }

    @Benchmark
    public void writeMessagesBuffered() throws IOException {
        write(OutputStream.nullOutputStream(), false);
    }

    private void write(OutputStream destination, boolean flush) throws IOException {
        try (BrotliOutputStream out = new BrotliOutputStream(destination, parameters)) {
            for (int offset = 0; offset < dataset.length; offset += messageSize) {
                out.write(dataset, offset, Math.min(messageSize, dataset.length - offset));
                if (flush) {
                    out.flush();
                }
            }
        }
    }
}
