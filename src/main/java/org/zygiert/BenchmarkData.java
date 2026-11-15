package org.zygiert;

import com.aayushatharva.brotli4j.decoder.BrotliInputStream;
import com.aayushatharva.brotli4j.decoder.Decoder;
import com.aayushatharva.brotli4j.decoder.DecoderJNI;
import com.aayushatharva.brotli4j.decoder.DirectDecompress;
import com.aayushatharva.brotli4j.encoder.Encoder;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.Random;

/**
 * Test data shared by all benchmarks, created and checked outside the measured code.
 */
public final class BenchmarkData {

    /** Fast quality: the per-call cost of the binding is most visible. */
    public static final int FAST_QUALITY = 1;
    /** Typical quality for compressing dynamic HTTP content. */
    public static final int PRODUCTION_QUALITY = 4;
    /** Lowest quality at which brotli uses an attached dictionary (1-4 give the same output without it). */
    public static final int DICTIONARY_QUALITY = 5;

    private static final byte[] DATASET = readDataset();

    private BenchmarkData() {
    }

    /** The whole XML dataset (compressible text). */
    public static byte[] dataset() {
        return DATASET;
    }

    /**
     * @param kind {@code text}: the first {@code size} bytes of the dataset; {@code random}: poorly compressible
     *             bytes from a fixed seed
     */
    public static byte[] input(String kind, int size) {
        switch (kind) {
            case "text":
                if (size > DATASET.length) {
                    throw new IllegalArgumentException("dataset has only " + DATASET.length + " bytes");
                }
                return Arrays.copyOf(DATASET, size);
            case "random":
                byte[] data = new byte[size];
                new Random(42).nextBytes(data);
                return data;
            default:
                throw new IllegalArgumentException("unknown input kind: " + kind);
        }
    }

    public static byte[] compress(byte[] data, int quality) {
        try {
            return Encoder.compress(data, Encoder.Parameters.create(quality));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /** Fails the trial if {@code compressed} doesn't decode to {@code expected}. */
    public static void checkRoundTrip(byte[] compressed, byte[] expected) {
        DirectDecompress result;
        try {
            result = Decoder.decompress(compressed);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        if (result.getResultStatus() != DecoderJNI.Status.DONE
                || !Arrays.equals(expected, result.getDecompressedData())) {
            throw new IllegalStateException("round trip failed: " + result.getResultStatus());
        }
    }

    /** Raw dictionary: the first 16 KiB of the dataset. */
    public static byte[] dictionary() {
        return Arrays.copyOf(DATASET, 16384);
    }

    /** A 1 KiB message from later in the dataset, sharing the dictionary's record structure. */
    public static byte[] dictionaryMessage() {
        return Arrays.copyOfRange(DATASET, 150000, 150000 + 1024);
    }

    /** Fails the trial unless {@code compressed} decodes to {@code expected} with {@code dictionary} attached. */
    public static void checkDictionaryRoundTrip(byte[] compressed, ByteBuffer dictionary, byte[] expected)
            throws IOException {
        BrotliInputStream in = new BrotliInputStream(new ByteArrayInputStream(compressed));
        in.attachDictionary(dictionary);
        checkStreamRoundTrip(in, expected);
    }

    /** Reads {@code in} to the end and closes it; returns the number of bytes read. */
    public static long drain(InputStream in, byte[] readBuffer) throws IOException {
        long total = 0;
        try (in) {
            int read;
            while ((read = in.read(readBuffer)) != -1) {
                total += read;
            }
        }
        return total;
    }

    /** Fails the trial unless {@code in} yields exactly {@code expected}; closes it. */
    public static void checkStreamRoundTrip(InputStream in, byte[] expected) throws IOException {
        byte[] decoded;
        try (in) {
            decoded = in.readAllBytes();
        }
        if (!Arrays.equals(expected, decoded)) {
            throw new IllegalStateException("stream round trip failed");
        }
    }

    public static ByteBuffer direct(byte[] data) {
        ByteBuffer buffer = ByteBuffer.allocateDirect(data.length);
        buffer.put(data).flip();
        return buffer;
    }

    private static byte[] readDataset() {
        try (InputStream in = BenchmarkData.class.getResourceAsStream("/dataset-formatted.xml")) {
            if (in == null) {
                throw new IllegalStateException("dataset-formatted.xml is missing");
            }
            return in.readAllBytes();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
