import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

final class BufferCopyToBufferDefaultBridgeAbiProbe {
    public static void main(String[] args) throws Exception {
        Class<?> buffer = Class.forName("kotlinx.io.Buffer");
        Method method = buffer.getDeclaredMethod(
            "copyTo$default",
            buffer,
            buffer,
            Long.TYPE,
            Long.TYPE,
            Integer.TYPE,
            Object.class
        );

        require(method.getReturnType() == Void.TYPE, "return descriptor must be V");
        require(method.getParameterTypes().length == 6, "descriptor must contain six parameters");
        require(Modifier.isPublic(method.getModifiers()), "method must be public");
        require(Modifier.isStatic(method.getModifiers()), "method must be static");
        require(method.isSynthetic(), "method must be synthetic");
        require(!method.isBridge(), "method must not carry the Java bridge flag");
        require(!Modifier.isFinal(method.getModifiers()), "method must not be final");
        require(!method.isVarArgs(), "method must not be varargs");
        require(method.getExceptionTypes().length == 0, "method must not declare checked exceptions");
        require(method.getDeclaredAnnotations().length == 0, "method must not declare annotations");

        Constructor<?> constructor = buffer.getDeclaredConstructor();
        Method writeByte = buffer.getDeclaredMethod("writeByte", Byte.TYPE);
        Method readByte = buffer.getDeclaredMethod("readByte");
        Method size = buffer.getDeclaredMethod("getSize");
        assertCopy(method, constructor, writeByte, readByte, size, 0L, 0L, 6, new byte[] {'A', 'B'});
        assertCopy(method, constructor, writeByte, readByte, size, 1L, 0L, 4, new byte[] {'B'});
        assertCopy(method, constructor, writeByte, readByte, size, 0L, 1L, 2, new byte[] {'A'});
        System.out.println("PASS: Buffer.copyTo$default JVM descriptor and ranges");
    }

    private static void assertCopy(Method method, Constructor<?> constructor,
                                   Method writeByte, Method readByte, Method size,
                                   long startIndex, long endIndex, int mask,
                                   byte[] expected) throws Exception {
        Object source = constructor.newInstance();
        writeByte.invoke(source, (byte) 'A');
        writeByte.invoke(source, (byte) 'B');
        Object target = constructor.newInstance();

        method.invoke(null, source, target, startIndex, endIndex, mask, null);

        require(((Long) size.invoke(source)) == 2L, "copyTo must not consume the source");
        require(((Long) size.invoke(target)) == (long) expected.length,
            "default bridge copied an unexpected byte count");
        for (byte value : expected) {
            require(((Byte) readByte.invoke(target)) == value, "default bridge copied unexpected bytes");
        }
        require(((Byte) readByte.invoke(source)) == (byte) 'A', "copyTo changed the source's first byte");
        require(((Byte) readByte.invoke(source)) == (byte) 'B', "copyTo changed the source's second byte");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }
}
