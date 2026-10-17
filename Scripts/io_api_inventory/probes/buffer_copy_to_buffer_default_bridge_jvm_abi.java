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
        System.out.println("PASS: Buffer.copyTo$default JVM descriptor");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }
}
