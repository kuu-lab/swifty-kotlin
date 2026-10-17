import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class BufferHeadAbiProbe {
    public static void main(String[] args) throws Exception {
        Class<?> bufferType = Class.forName("kotlinx.io.Buffer");
        Class<?> segmentType = Class.forName("kotlinx.io.Segment");
        Method getter = bufferType.getDeclaredMethod("getHead");
        Method setter = bufferType.getDeclaredMethod("setHead", segmentType);

        requireAccessor(getter, segmentType, new Class<?>[0], "getHead");
        requireAccessor(setter, void.class, new Class<?>[] {segmentType}, "setHead");

        Object target = bufferType.getConstructor().newInstance();
        if (getter.invoke(target) != null) {
            throw new AssertionError("new Buffer.head must be null");
        }

        Object source = bufferType.getConstructor().newInstance();
        Method write = bufferType.getDeclaredMethod("write", byte[].class, int.class, int.class);
        write.invoke(source, new byte[] {11, 22, 33}, 0, 3);
        Object segment = getter.invoke(source);
        if (segment == null || !segmentType.isInstance(segment)) {
            throw new AssertionError("writing bytes must create a head segment");
        }

        setter.invoke(target, segment);
        if (getter.invoke(target) != segment) {
            throw new AssertionError("setHead must preserve the assigned segment");
        }

        setter.invoke(target, new Object[] {null});
        if (getter.invoke(target) != null) {
            throw new AssertionError("setHead must accept null");
        }

        System.out.println("getHead=public-final-synthetic;return=Segment");
        System.out.println("setHead=public-final-synthetic;parameter=Segment;return=void");
        System.out.println("headInitiallyNull=true");
        System.out.println("headUpdatePreservesIdentity=true");
        System.out.println("headSetterAcceptsNull=true");
    }

    private static void requireAccessor(
            Method method, Class<?> returnType, Class<?>[] parameterTypes, String name) {
        int modifiers = method.getModifiers();
        if (method.getReturnType() != returnType
                || !java.util.Arrays.equals(method.getParameterTypes(), parameterTypes)
                || !Modifier.isPublic(modifiers)
                || !Modifier.isFinal(modifiers)
                || Modifier.isStatic(modifiers)
                || !method.isSynthetic()) {
            throw new AssertionError("unexpected " + name + " JVM ABI: " + method);
        }
    }
}
