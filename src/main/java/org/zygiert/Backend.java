package org.zygiert;

import com.aayushatharva.brotli4j.Brotli4jLoader;
import com.aayushatharva.brotli4j.decoder.DecoderJNI;
import com.aayushatharva.brotli4j.encoder.EncoderJNI;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.lang.reflect.Field;

/**
 * Loads brotli4j and fails the trial unless the expected backend is active, so results can't be filed under
 * the wrong name. The expected backend comes from {@code -Dbenchmark.backend}:
 * <ul>
 *     <li>{@code base}: the JNI classes of the jar root (brotli4j main before the FFM port, or a build with
 *     {@code -Djdk.util.jar.enableMultiRelease=false})</li>
 *     <li>{@code jni}: the JDK 22+ classes of a local build with {@code -Dbrotli4j.backend=jni}</li>
 *     <li>{@code ffm}: the JDK 22+ classes of a local build calling brotli through FFM</li>
 * </ul>
 */
public final class Backend {

    public static final String PROPERTY = "benchmark.backend";

    private Backend() {
    }

    /** Call from every {@code @Setup(Level.Trial)}. */
    public static void verify() {
        Brotli4jLoader.ensureAvailability();
        String expected = System.getProperty(PROPERTY);
        if (expected == null) {
            throw new IllegalStateException("Set -jvmArgsPrepend -D" + PROPERTY + "=base|jni|ffm");
        }
        String encoder = encoderBackend();
        String decoder = decoderBackend();
        if (!expected.equals(encoder) || !expected.equals(decoder)) {
            throw new IllegalStateException("Expected backend " + expected + ", but the encoder uses " + encoder
                    + " and the decoder " + decoder);
        }
    }

    private static String encoderBackend() {
        try {
            EncoderJNI.Wrapper wrapper = new EncoderJNI.Wrapper(1, -1, -1, null);
            try {
                return backendOf(wrapper);
            } finally {
                wrapper.destroy();
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static String decoderBackend() {
        try {
            DecoderJNI.Wrapper wrapper = new DecoderJNI.Wrapper(1);
            try {
                return backendOf(wrapper);
            } finally {
                wrapper.destroy();
            }
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    /**
     * Only the JDK 22+ wrappers have a {@code caller} field; its class tells FFM and JNI apart.
     */
    private static String backendOf(Object wrapper) {
        Field caller;
        try {
            caller = wrapper.getClass().getDeclaredField("caller");
        } catch (NoSuchFieldException e) {
            return "base";
        }
        caller.setAccessible(true);
        String name;
        try {
            name = caller.get(wrapper).getClass().getSimpleName();
        } catch (IllegalAccessException e) {
            throw new IllegalStateException(e);
        }
        switch (name) {
            case "FfmNativeFunctionCaller":
                return "ffm";
            case "JniNativeFunctionCaller":
                return "jni";
            default:
                throw new IllegalStateException("Unknown caller " + name);
        }
    }
}
