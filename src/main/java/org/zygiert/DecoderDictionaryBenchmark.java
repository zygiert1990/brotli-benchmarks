package org.zygiert;

import com.aayushatharva.brotli4j.decoder.BrotliInputStream;
import com.aayushatharva.brotli4j.decoder.Decoder;
import com.aayushatharva.brotli4j.decoder.DecoderJNI;
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
import org.openjdk.jmh.annotations.Warmup;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.concurrent.TimeUnit;

/**
 * Decompressing a message compressed with a 16 KiB raw dictionary: attaching the dictionary to a new decoder
 * and decoding.
 */
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.MICROSECONDS)
@Fork(value = 3, jvmArgsAppend = {"-Xms2g", "-Xmx2g", "-XX:+AlwaysPreTouch", "-XX:+UseG1GC",
        "--enable-native-access=ALL-UNNAMED"})
@Warmup(iterations = 3, time = 3, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 5, timeUnit = TimeUnit.SECONDS)
@State(Scope.Thread)
public class DecoderDictionaryBenchmark {

    private ByteBuffer dictionary;
    private byte[] compressed;
    private final byte[] readBuffer = new byte[8192];

    @Setup(Level.Trial)
    public void setup() throws Exception {
        Backend.verify();
        dictionary = BenchmarkData.direct(BenchmarkData.dictionary());
        byte[] message = BenchmarkData.dictionaryMessage();
        PreparedDictionary prepared = Encoder.prepareDictionary(dictionary, 0);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try (BrotliOutputStream encoder = new BrotliOutputStream(out,
                Encoder.Parameters.create(BenchmarkData.DICTIONARY_QUALITY))) {
            encoder.attachDictionary(prepared);
            encoder.write(message);
        } finally {
            ((AutoCloseable) prepared).close();
        }
        compressed = out.toByteArray();
        BenchmarkData.checkDictionaryRoundTrip(compressed, dictionary, message);
        // Otherwise the message doesn't refer to the dictionary and the benchmark measures plain decoding.
        if (Decoder.decompress(compressed).getResultStatus() == DecoderJNI.Status.DONE) {
            throw new IllegalStateException("the message decodes without the dictionary");
        }
    }

    @Benchmark
    public long decompressMessageWithDictionary() throws IOException {
        BrotliInputStream in = new BrotliInputStream(new ByteArrayInputStream(compressed));
        in.attachDictionary(dictionary);
        return BenchmarkData.drain(in, readBuffer);
    }
}
