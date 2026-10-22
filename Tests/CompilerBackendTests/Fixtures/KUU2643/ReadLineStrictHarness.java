import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.InvocationTargetException;
import java.nio.charset.StandardCharsets;
import kotlinx.io.Buffer;
import kotlinx.io.EOFException;
import kotlinx.io.Source;
import kotlinx.io.Utf8Kt;

public final class ReadLineStrictHarness {
    private interface ThrowingRunnable {
        void run() throws Exception;
    }

    private static final class MemorySource implements Source, Buffer {
        private final byte[] bytes;
        private int position;
        private long lastToIndex = Long.MIN_VALUE;

        MemorySource(String value) {
            bytes = value.getBytes(StandardCharsets.UTF_8);
        }

        @Override public Buffer getBuffer() { return this; }
        @Override public long getSize() { return bytes.length - position; }
        @Override public byte get(long index) { return bytes[position + (int) index]; }

        @Override public void require(long byteCount) {
            if (getSize() < byteCount) throw new EOFException();
        }

        @Override public long indexOf(byte value, long fromIndex, long toIndex) {
            lastToIndex = toIndex;
            long end = Math.min(toIndex, getSize());
            for (long index = fromIndex; index < end; index++) {
                if (get(index) == value) return index;
            }
            return -1L;
        }

        @Override public String readString(long byteCount) {
            String result = new String(bytes, position, (int) byteCount, StandardCharsets.UTF_8);
            position += (int) byteCount;
            return result;
        }

        @Override public void skip(long byteCount) { position += (int) byteCount; }
        @Override public boolean request(long byteCount) { return getSize() >= byteCount; }
    }

    private static void equal(Object expected, Object actual, String label) {
        if (!expected.equals(actual)) throw new AssertionError(label + ": expected " + expected + ", got " + actual);
    }

    private static Object callDefault(Source source, long limit, int mask) throws Exception {
        Method bridge = Utf8Kt.class.getDeclaredMethod(
            "readLineStrict$default", Source.class, long.class, int.class, Object.class);
        return bridge.invoke(null, source, limit, mask, null);
    }

    private static void expectEof(ThrowingRunnable body, String label) throws Exception {
        try {
            body.run();
            throw new AssertionError(label + ": expected EOFException");
        } catch (EOFException expected) {
            // The source operation must leave the failing line unconsumed.
        } catch (InvocationTargetException failure) {
            if (!(failure.getCause() instanceof EOFException)) throw failure;
        }
    }

    public static void main(String[] args) throws Exception {
        Method bridge = Utf8Kt.class.getDeclaredMethod(
            "readLineStrict$default", Source.class, long.class, int.class, Object.class);
        if (!Modifier.isPublic(bridge.getModifiers()) || !Modifier.isStatic(bridge.getModifiers()) ||
            !bridge.isSynthetic() || bridge.isBridge()) {
            throw new AssertionError("Default bridge has the wrong JVM flags");
        }

        MemorySource defaultBridge = new MemorySource("line\r\n");
        equal("line", callDefault(defaultBridge, 0L, 1), "default bridge result");
        equal(Long.MAX_VALUE, defaultBridge.lastToIndex, "default limit passed to indexOf");
        equal(0L, defaultBridge.getSize(), "default bridge consumes CRLF");

        MemorySource lfAtLimit = new MemorySource("abc\nz");
        equal("abc", Utf8Kt.readLineStrict(lfAtLimit, 3L), "LF exactly at limit");
        equal("z", lfAtLimit.readString(1L), "LF boundary consumption");

        MemorySource crlfAtLimit = new MemorySource("abc\r\nz");
        equal("abc", Utf8Kt.readLineStrict(crlfAtLimit, 3L), "CRLF exactly at limit");
        equal("z", crlfAtLimit.readString(1L), "CRLF boundary consumption");

        MemorySource lfBeforeLimit = new MemorySource("a\nb");
        equal("a", Utf8Kt.readLineStrict(lfBeforeLimit, 3L), "LF before limit");
        equal("b", lfBeforeLimit.readString(1L), "LF before limit consumption");

        MemorySource tooLong = new MemorySource("abcd\n");
        expectEof(() -> Utf8Kt.readLineStrict(tooLong, 3L), "line longer than limit");
        equal(5L, tooLong.getSize(), "over-limit failure preserves source");

        MemorySource negative = new MemorySource("x\n");
        try {
            Utf8Kt.readLineStrict(negative, -1L);
            throw new AssertionError("negative limit: expected IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
            equal("limit (-1) < 0", expected.getMessage(), "negative limit message");
        }
        equal(2L, negative.getSize(), "negative limit preserves source");

        MemorySource empty = new MemorySource("");
        expectEof(() -> callDefault(empty, 0L, 1), "empty source");
        equal(0L, empty.getSize(), "empty source remains empty");

        MemorySource noTerminator = new MemorySource("unfinished");
        expectEof(() -> callDefault(noTerminator, 0L, 1), "default limit without LF");
        equal(10L, noTerminator.getSize(), "missing terminator preserves source");

        System.out.println("KUU-2643 actual Source.readLineStrict PASS");
    }
}
