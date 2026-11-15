package org.zygiert;

import com.aayushatharva.brotli4j.encoder.BrotliOutputStream;
import com.aayushatharva.brotli4j.encoder.Encoder;
import com.aayushatharva.brotli4j.encoder.PreparedDictionary;
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
import org.openjdk.jmh.annotations.TearDown;
import org.openjdk.jmh.annotations.Warmup;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.TimeUnit;

/**
 * Encoder dictionaries. {@code prepareAndCloseDictionary} measures preparing and freeing a 16 KiB dictionary
 * (mostly brotli's own work); {@code compressMessageWithDictionary} reuses one prepared dictionary for each
 * message, the way it is meant to be used.
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Benchmark)
public class EncoderDictionaryBenchmark {

    private ByteBuffer dictionary;
    private PreparedDictionary prepared;
    private byte[] message;
    private Encoder.Parameters parameters;

    @Setup(Level.Trial)
    public void setup() throws IOException {
        Backend.verify();
        dictionary = BenchmarkData.direct(BenchmarkData.dictionary());
        prepared = Encoder.prepareDictionary(dictionary, 0);
        message = BenchmarkData.dictionaryMessage();
        parameters = Encoder.Parameters.create(BenchmarkData.DICTIONARY_QUALITY);

        ByteArrayOutputStream compressed = new ByteArrayOutputStream();
        compress(compressed);
        BenchmarkData.checkDictionaryRoundTrip(compressed.toByteArray(), dictionary, message);
        // Otherwise the dictionary was not used and the benchmark measures plain compression.
        if (compressed.size() >= BenchmarkData.compress(message, BenchmarkData.DICTIONARY_QUALITY).length) {
            throw new IllegalStateException("the dictionary doesn't make the message smaller");
        }
    }

    @TearDown(Level.Trial)
    public void tearDown() throws Exception {
        ((AutoCloseable) prepared).close();
    }

    @Benchmark
    public void prepareAndCloseDictionary() throws Exception {
        ((AutoCloseable) Encoder.prepareDictionary(dictionary, 0)).close();
    }

    @Benchmark
    public void compressMessageWithDictionary() throws IOException {
        compress(OutputStream.nullOutputStream());
    }

    private void compress(OutputStream destination) throws IOException {
        try (BrotliOutputStream out = new BrotliOutputStream(destination, parameters)) {
            out.attachDictionary(prepared);
            out.write(message);
        }
    }
}
