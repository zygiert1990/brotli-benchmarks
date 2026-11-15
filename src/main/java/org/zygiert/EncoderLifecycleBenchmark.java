package org.zygiert;

import com.aayushatharva.brotli4j.encoder.BrotliOutputStream;
import com.aayushatharva.brotli4j.encoder.Encoder;
import com.aayushatharva.brotli4j.encoder.EncoderJNI;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.BenchmarkMode;
import org.openjdk.jmh.annotations.Fork;
import org.openjdk.jmh.annotations.Level;
import org.openjdk.jmh.annotations.Measurement;
import org.openjdk.jmh.annotations.Mode;
import org.openjdk.jmh.annotations.OutputTimeUnit;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.annotations.Threads;
import org.openjdk.jmh.annotations.Warmup;

import java.io.IOException;
import java.io.OutputStream;
import java.util.concurrent.TimeUnit;

/**
 * Creating and destroying an encoder, without compressing anything. Every one-shot compression and every
 * stream pays this. The FFM wrapper opens and closes a shared arena, whose close synchronizes with all
 * running threads, so each case also runs on four threads.
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class EncoderLifecycleBenchmark {

    /** The default buffer size of the brotli4j streams. */
    private static final int BUFFER_SIZE = 16384;

    private final Encoder.Parameters parameters = Encoder.Parameters.create(BenchmarkData.PRODUCTION_QUALITY);

    @Setup(Level.Trial)
    public void setup() {
        Backend.verify();
    }

    /** Native state and input buffer only. */
    @Benchmark
    public void createAndDestroyWrapper() throws IOException {
        createAndDestroy();
    }

    @Benchmark
    @Threads(4)
    public void createAndDestroyWrapperOnFourThreads() throws IOException {
        createAndDestroy();
    }

    /** Adds what closing a stream does: finishing an empty brotli stream (push and pull). */
    @Benchmark
    public void createAndCloseEmptyStream() throws IOException {
        createAndClose();
    }

    @Benchmark
    @Threads(4)
    public void createAndCloseEmptyStreamOnFourThreads() throws IOException {
        createAndClose();
    }

    private void createAndDestroy() throws IOException {
        EncoderJNI.Wrapper wrapper = new EncoderJNI.Wrapper(BUFFER_SIZE, parameters.quality(), parameters.lgwin(),
                parameters.mode());
        wrapper.destroy();
    }

    private void createAndClose() throws IOException {
        new BrotliOutputStream(OutputStream.nullOutputStream(), parameters, BUFFER_SIZE).close();
    }
}
