import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class SourceByteArrayDefaultBridgeAbiProbe {
    private static final String READ_AT_MOST_ROW = "jvm-281a58349eb012c0";
    private static final String READ_TO_ROW = "jvm-d0a5256163899ef7";
    private static int assertionCount;

    public static void main(String[] args) throws Exception {
        Class<?> source = Class.forName("kotlinx.io.Source");
        Class<?> buffer = Class.forName("kotlinx.io.Buffer");
        Class<?> sources = Class.forName("kotlinx.io.SourcesKt");
        Method write = buffer.getDeclaredMethod("write", byte[].class, int.class, int.class);
        Method readAtMostTo = source.getDeclaredMethod("readAtMostTo$default", source, byte[].class,
                int.class, int.class, int.class, Object.class);
        Method readTo = sources.getDeclaredMethod("readTo$default", source, byte[].class,
                int.class, int.class, int.class, Object.class);

        verifyBridge(readAtMostTo, Integer.TYPE, source, byte[].class, int.class, int.class, int.class, Object.class);
        verifyBridge(readTo, Void.TYPE, source, byte[].class, int.class, int.class, int.class, Object.class);
        verifyDefaultCalls(buffer, write, readAtMostTo, readTo);
        verifyInvalidArguments(buffer, write, readAtMostTo, readTo);

        System.out.println("assertions=" + assertionCount);
        System.out.println(READ_AT_MOST_ROW + "=public-static-synthetic:(Lkotlinx/io/Source;[BIIILjava/lang/Object;)I");
        System.out.println(READ_TO_ROW + "=public-static-synthetic:(Lkotlinx/io/Source;[BIIILjava/lang/Object;)V");
    }

    private static void verifyBridge(Method method, Class<?> result, Class<?>... parameters) {
        int flags = method.getModifiers();
        if (!Modifier.isPublic(flags) || !Modifier.isStatic(flags) || !method.isSynthetic()
                || method.isBridge() || method.getReturnType() != result
                || !java.util.Arrays.equals(method.getParameterTypes(), parameters)) {
            throw new AssertionError("unexpected JVM default bridge: " + method);
        }
        assertionCount++;
    }

    private static void verifyDefaultCalls(Class<?> bufferClass, Method write, Method readAtMostTo,
            Method readTo) throws Exception {
        byte[] startDefault = new byte[] {99, 99, 99, 99};
        Object startSource = source(bufferClass, write, 10, 20, 30);
        int startCount = (Integer) readAtMostTo.invoke(null, startSource, startDefault, -1, 2, 2, null);
        equal(2, startCount, "readAtMostTo default start count");
        bytes(new byte[] {10, 20, 99, 99}, startDefault, "readAtMostTo default start");

        byte[] endDefault = new byte[] {99, 99, 99, 99};
        Object endSource = source(bufferClass, write, 1, 2, 3);
        int endCount = (Integer) readAtMostTo.invoke(null, endSource, endDefault, 1, -1, 4, null);
        equal(3, endCount, "readAtMostTo default end count");
        bytes(new byte[] {99, 1, 2, 3}, endDefault, "readAtMostTo default end");

        byte[] bothDefaults = new byte[] {99, 99, 99};
        Object bothSource = source(bufferClass, write, 4, 5);
        int bothCount = (Integer) readAtMostTo.invoke(null, bothSource, bothDefaults, -1, -1, 6, null);
        equal(2, bothCount, "readAtMostTo both defaults count");
        bytes(new byte[] {4, 5, 99}, bothDefaults, "readAtMostTo both defaults");

        byte[] readToStartDefault = new byte[] {99, 99, 99, 99};
        readTo.invoke(null, source(bufferClass, write, 6, 7, 8), readToStartDefault, -1, 2, 2, null);
        bytes(new byte[] {6, 7, 99, 99}, readToStartDefault, "readTo default start");

        byte[] readToEndDefault = new byte[] {99, 99, 99, 99};
        readTo.invoke(null, source(bufferClass, write, 11, 12, 13), readToEndDefault, 1, -1, 4, null);
        bytes(new byte[] {99, 11, 12, 13}, readToEndDefault, "readTo default end");

        byte[] readToBothDefaults = new byte[] {99, 99};
        readTo.invoke(null, source(bufferClass, write, 21, 22), readToBothDefaults, -1, -1, 6, null);
        bytes(new byte[] {21, 22}, readToBothDefaults, "readTo both defaults");

        try {
            readTo.invoke(null, source(bufferClass, write, 31, 32), new byte[3], -1, -1, 6, null);
            throw new AssertionError("readTo default bridge did not preserve EOFException");
        } catch (InvocationTargetException error) {
            if (!(error.getCause() instanceof java.io.EOFException)) {
                throw new AssertionError("readTo default bridge changed EOF exception", error.getCause());
            }
            assertionCount++;
        }
    }

    private static void verifyInvalidArguments(Class<?> bufferClass, Method write, Method readAtMostTo,
            Method readTo) throws Exception {
        expectFailure(readAtMostTo,
                new Object[] {source(bufferClass, write, 61), new byte[4], 4, 1, 0, null},
                IllegalArgumentException.class, "readAtMostTo start after end");
        expectFailure(readAtMostTo,
                new Object[] {source(bufferClass, write, 62), new byte[4], 1, 5, 0, null},
                IndexOutOfBoundsException.class, "readAtMostTo end beyond destination");
        expectFailure(readAtMostTo,
                new Object[] {source(bufferClass, write, 63), new byte[4], -1, 2, 0, null},
                IndexOutOfBoundsException.class, "readAtMostTo negative start");
        expectFailure(readTo,
                new Object[] {source(bufferClass, write, 64), new byte[3], 2, 0, 0, null},
                IllegalArgumentException.class, "readTo start after end");
        expectFailure(readTo,
                new Object[] {source(bufferClass, write, 65), new byte[3], -1, 3, 0, null},
                IndexOutOfBoundsException.class, "readTo negative start");
        expectFailure(readTo,
                new Object[] {source(bufferClass, write, 66), new byte[3], 0, 4, 0, null},
                IndexOutOfBoundsException.class, "readTo end beyond destination");
    }

    private static void expectFailure(Method method, Object[] arguments, Class<? extends Throwable> expected,
            String label) throws Exception {
        try {
            method.invoke(null, arguments);
            throw new AssertionError(label + " did not throw " + expected.getSimpleName());
        } catch (InvocationTargetException error) {
            if (!expected.isInstance(error.getCause())) {
                throw new AssertionError(label + " threw " + error.getCause(), error.getCause());
            }
            assertionCount++;
        }
    }

    private static Object source(Class<?> bufferClass, Method write, int... values) throws Exception {
        Object result = bufferClass.getDeclaredConstructor().newInstance();
        byte[] bytes = new byte[values.length];
        for (int index = 0; index < values.length; index++) bytes[index] = (byte) values[index];
        write.invoke(result, bytes, 0, bytes.length);
        return result;
    }

    private static void equal(int expected, int actual, String label) {
        if (expected != actual) throw new AssertionError(label + ": expected " + expected + ", got " + actual);
        assertionCount++;
    }

    private static void bytes(byte[] expected, byte[] actual, String label) {
        if (!java.util.Arrays.equals(expected, actual)) {
            throw new AssertionError(label + ": expected " + java.util.Arrays.toString(expected)
                    + ", got " + java.util.Arrays.toString(actual));
        }
        assertionCount++;
    }
}
