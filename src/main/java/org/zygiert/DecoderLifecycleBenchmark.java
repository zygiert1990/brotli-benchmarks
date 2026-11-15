package org.zygiert;

import com.aayushatharva.brotli4j.decoder.BrotliInputStream;
import com.aayushatharva.brotli4j.decoder.DecoderJNI;
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

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

/**
 * Creating and destroying a decoder, without decompressing anything. Every one-shot decompression and every
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
public class DecoderLifecycleBenchmark {

    /** The default buffer size of the brotli4j streams. */
    private static final int BUFFER_SIZE = 16384;
    private static final byte[] EMPTY = new byte[0];

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

    /** Adds the stream objects around the wrapper; nothing is read. */
    @Benchmark
    public void createAndCloseStream() throws IOException {
        createAndClose();
    }

    @Benchmark
    @Threads(4)
    public void createAndCloseStreamOnFourThreads() throws IOException {
        createAndClose();
    }

    private static void createAndDestroy() throws IOException {
        new DecoderJNI.Wrapper(BUFFER_SIZE).destroy();
    }

    private static void createAndClose() throws IOException {
        new BrotliInputStream(new ByteArrayInputStream(EMPTY), BUFFER_SIZE).close();
    }
}
