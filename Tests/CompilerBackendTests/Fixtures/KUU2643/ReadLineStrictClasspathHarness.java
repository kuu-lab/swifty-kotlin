import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import kotlinx.io.Buffer;
import kotlinx.io.EOFException;
import kotlinx.io.ReadLineStrictKt;
import kotlinx.io.SourcesKt;
import kotlinx.io.Source;

public final class ReadLineStrictClasspathHarness {
    private static final class MemorySource implements Source, Buffer {
        private final byte[] bytes;
        private int position;
        MemorySource(String value) { bytes = value.getBytes(StandardCharsets.UTF_8); }
        @Override public Buffer getBuffer() { return this; }
        @Override public long getSize() { return bytes.length - position; }
        @Override public byte get(long index) { return bytes[position + (int) index]; }
        @Override public void require(long byteCount) {
            if (getSize() < byteCount) throw new EOFException();
        }
        @Override public boolean request(long byteCount) { return getSize() >= byteCount; }
        @Override public void skip(long byteCount) { position += (int) byteCount; }
    }

    private static void equal(Object expected, Object actual, String label) {
        if (!expected.equals(actual)) throw new AssertionError(label + ": expected " + expected + ", got " + actual);
    }

    private static Object callDefault(Source source, long limit, int mask) throws Exception {
        Method bridge = ReadLineStrictKt.class.getDeclaredMethod(
            "readLineStrictActual$default", Source.class, long.class, int.class, Object.class);
        try {
            return bridge.invoke(null, source, limit, mask, null);
        } catch (InvocationTargetException failure) {
            throw (Exception) failure.getCause();
        }
    }

    private static void expectEof(Runnable body, String label) {
        try {
            body.run();
            throw new AssertionError(label + ": expected EOFException");
        } catch (EOFException expected) {
            // The failing line must remain unconsumed.
        }
    }

    public static void main(String[] args) throws Exception {
        Method bridge = ReadLineStrictKt.class.getDeclaredMethod(
            "readLineStrictActual$default", Source.class, long.class, int.class, Object.class);
        if (!Modifier.isPublic(bridge.getModifiers()) || !Modifier.isStatic(bridge.getModifiers()) ||
            !bridge.isSynthetic() || bridge.isBridge()) {
            throw new AssertionError("Default bridge has the wrong JVM flags");
        }

        MemorySource defaultBridge = new MemorySource("line\r\n");
        equal("line", callDefault(defaultBridge, 0L, 1), "default bridge result");
        equal(Long.MAX_VALUE, SourcesKt.lastToIndex, "default limit passed to indexOf");
        equal(0L, defaultBridge.getSize(), "default bridge consumes CRLF");

        MemorySource crlfAtLimit = new MemorySource("abc\r\nz");
        equal("abc", ReadLineStrictKt.readLineStrictActual(crlfAtLimit, 3L), "CRLF at limit");
        equal(1L, crlfAtLimit.getSize(), "CRLF boundary remainder");

        MemorySource tooLong = new MemorySource("abcd\n");
        expectEof(() -> ReadLineStrictKt.readLineStrictActual(tooLong, 3L), "line longer than limit");
        equal(5L, tooLong.getSize(), "over-limit failure preserves source");

        System.out.println("KUU-2643 imported JVM classpath PASS");
    }
}
