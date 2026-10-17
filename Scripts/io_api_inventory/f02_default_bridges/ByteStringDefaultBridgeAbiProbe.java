import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;

public final class ByteStringDefaultBridgeAbiProbe {
    private static final Class<?> OBJECT = Object.class;

    public static void main(String[] args) throws Throwable {
        Class<?> byteString = Class.forName("kotlinx.io.bytestring.ByteString");
        Method toByteArray = bridge(byteString, "toByteArray$default", byte[].class,
                byteString, int.class, int.class, int.class, OBJECT);
        Method substring = bridge(byteString, "substring$default", byteString,
                byteString, int.class, int.class, int.class, OBJECT);
        Method copyInto = bridge(byteString, "copyInto$default", void.class,
                byteString, byte[].class, int.class, int.class, int.class, int.class, OBJECT);
        Object value = byteString.getConstructor(byte[].class, int.class, int.class)
                .newInstance(new byte[]{1, 2, 3, 4, 5, 6}, 0, 6);

        checkArray("toByteArray mask 1", new byte[]{1, 2, 3},
                (byte[]) invoke(toByteArray, value, -1, 3, 1, null));
        checkArray("toByteArray mask 2", new byte[]{4, 5, 6},
                (byte[]) invoke(toByteArray, value, 3, -1, 2, null));
        checkArray("toByteArray mask 3", new byte[]{1, 2, 3, 4, 5, 6},
                (byte[]) invoke(toByteArray, value, -1, -1, 3, null));
        expectFailure("toByteArray reversed range", IllegalArgumentException.class,
                () -> invoke(toByteArray, value, 2, 1, 0, null));
        expectFailure("toByteArray out of bounds", IndexOutOfBoundsException.class,
                () -> invoke(toByteArray, value, 0, 7, 0, null));

        Object suffix = invoke(substring, value, 2, -1, 2, null);
        checkArray("substring mask 2", new byte[]{3, 4, 5, 6},
                (byte[]) byteString.getDeclaredMethod("toByteArray", int.class, int.class)
                        .invoke(suffix, 0, 4));
        expectFailure("substring reversed range", IllegalArgumentException.class,
                () -> invoke(substring, value, 2, 1, 0, null));
        expectFailure("substring out of bounds", IndexOutOfBoundsException.class,
                () -> invoke(substring, value, 0, 7, 0, null));

        byte[] allDefaults = new byte[8];
        invoke(copyInto, value, allDefaults, -1, -1, -1, 14, null);
        checkArray("copyInto mask 14", new byte[]{1, 2, 3, 4, 5, 6, 0, 0}, allDefaults);
        byte[] defaultOffset = new byte[8];
        invoke(copyInto, value, defaultOffset, -1, 2, 4, 2, null);
        checkArray("copyInto mask 2", new byte[]{3, 4, 0, 0, 0, 0, 0, 0}, defaultOffset);
        byte[] defaultStart = new byte[8];
        invoke(copyInto, value, defaultStart, 2, -1, 4, 4, null);
        checkArray("copyInto mask 4", new byte[]{0, 0, 1, 2, 3, 4, 0, 0}, defaultStart);
        byte[] defaultEnd = new byte[8];
        invoke(copyInto, value, defaultEnd, 3, 3, -1, 8, null);
        checkArray("copyInto mask 8", new byte[]{0, 0, 0, 4, 5, 6, 0, 0}, defaultEnd);
        expectFailure("copyInto reversed range", IllegalArgumentException.class,
                () -> invoke(copyInto, value, new byte[8], 0, 2, 1, 0, null));
        expectFailure("copyInto destination overflow", IndexOutOfBoundsException.class,
                () -> invoke(copyInto, value, new byte[4], 0, 0, 6, 0, null));

        System.out.println("ByteString default bridge JVM descriptors, flags, masks, and exception types: PASS");
    }

    private static Method bridge(Class<?> owner, String name, Class<?> returnType,
                                 Class<?>... parameterTypes) throws Exception {
        Method method = owner.getDeclaredMethod(name, parameterTypes);
        int modifiers = method.getModifiers();
        if (method.getReturnType() != returnType
                || !Modifier.isPublic(modifiers)
                || !Modifier.isStatic(modifiers)
                || !method.isSynthetic()
                || method.isBridge()
                || method.isVarArgs()) {
            throw new AssertionError("unexpected JVM bridge descriptor or flags: " + method
                    + "; modifiers=" + Modifier.toString(modifiers)
                    + "; synthetic=" + method.isSynthetic()
                    + "; bridge=" + method.isBridge());
        }
        long sameName = Arrays.stream(owner.getDeclaredMethods())
                .filter(candidate -> candidate.getName().equals(name)).count();
        if (sameName != 1) throw new AssertionError("duplicate JVM bridge overload: " + name);
        return method;
    }

    private static Object invoke(Method method, Object... arguments) throws Throwable {
        try {
            return method.invoke(null, arguments);
        } catch (InvocationTargetException failure) {
            throw failure.getCause();
        }
    }

    private static void expectFailure(String label, Class<? extends Throwable> expected,
                                      ThrowingAction action) throws Throwable {
        try {
            action.run();
        } catch (Throwable failure) {
            if (expected.isInstance(failure)) return;
            throw new AssertionError(label + " threw " + failure.getClass().getName()
                    + ", expected " + expected.getName(), failure);
        }
        throw new AssertionError(label + " did not throw " + expected.getName());
    }

    private static void checkArray(String label, byte[] expected, byte[] actual) {
        if (!Arrays.equals(expected, actual)) {
            throw new AssertionError(label + ": expected " + Arrays.toString(expected)
                    + ", actual " + Arrays.toString(actual));
        }
    }

    @FunctionalInterface
    private interface ThrowingAction {
        void run() throws Throwable;
    }
}
