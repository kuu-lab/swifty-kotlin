import java.io.OutputStream;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import kotlinx.io.Buffer;

public final class BufferOutputStreamDefaultBridgeAbi {
    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static String typeDescriptor(Class<?> type) {
        if (type == void.class) return "V";
        if (type == long.class) return "J";
        if (type == int.class) return "I";
        if (type.isPrimitive()) throw new AssertionError("Unexpected primitive type: " + type);
        if (type.isArray()) return type.getName().replace('.', '/');
        return "L" + type.getName().replace('.', '/') + ";";
    }

    private static String methodDescriptor(Method method) {
        StringBuilder descriptor = new StringBuilder("(");
        for (Class<?> parameter : method.getParameterTypes()) {
            descriptor.append(typeDescriptor(parameter));
        }
        return descriptor.append(')').append(typeDescriptor(method.getReturnType())).toString();
    }

    private static void verify(String name, String expectedDescriptor, Class<?>... parameters)
            throws ReflectiveOperationException {
        Class<?> facade = Class.forName("kotlinx.io.BuffersJvmKt");
        Method method = facade.getDeclaredMethod(name, parameters);
        int modifiers = method.getModifiers();
        require(Modifier.isPublic(modifiers), name + " is not public");
        require(Modifier.isStatic(modifiers), name + " is not static");
        require(method.isSynthetic(), name + " is not synthetic");
        require(!method.isBridge(), name + " is unexpectedly a bridge method");
        require(method.getReturnType() == void.class, name + " does not return void");
        String descriptor = methodDescriptor(method);
        require(expectedDescriptor.equals(descriptor), name + " descriptor: " + descriptor);
        System.out.println("PASS " + name + " " + descriptor + " public static synthetic bridge=false");
    }

    public static void main(String[] args) throws ReflectiveOperationException {
        verify(
                "copyTo$default",
                "(Lkotlinx/io/Buffer;Ljava/io/OutputStream;JJILjava/lang/Object;)V",
                Buffer.class, OutputStream.class, long.class, long.class, int.class, Object.class);
        verify(
                "readTo$default",
                "(Lkotlinx/io/Buffer;Ljava/io/OutputStream;JILjava/lang/Object;)V",
                Buffer.class, OutputStream.class, long.class, int.class, Object.class);
    }
}
