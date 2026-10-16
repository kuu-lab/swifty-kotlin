import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.invoke.MethodType;
import java.nio.ByteBuffer;
import java.util.Arrays;

public final class ByteBufferGetByteStringJvmAbiProbe {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.bytestring.ByteStringJvmExtKt");
        Method[] matches = Arrays.stream(owner.getDeclaredMethods())
            .filter(method -> method.getName().equals("getByteString$default"))
            .toArray(Method[]::new);
        require(matches.length == 1, "expected one getByteString$default method");

        Method method = matches[0];
        String descriptor = MethodType.methodType(method.getReturnType(), method.getParameterTypes())
            .toMethodDescriptorString();
        String expectedDescriptor =
            "(Ljava/nio/ByteBuffer;IILjava/lang/Object;)Lkotlinx/io/bytestring/ByteString;";
        require(descriptor.equals(expectedDescriptor), "descriptor: " + descriptor);
        require(Modifier.isPublic(method.getModifiers()), "method must be public");
        require(Modifier.isStatic(method.getModifiers()), "method must be static");
        require(method.isSynthetic(), "method must be synthetic");
        require(!method.isBridge(), "method must not carry ACC_BRIDGE");
        require(Arrays.equals(method.getParameterTypes(), new Class<?>[] {
            ByteBuffer.class, int.class, int.class, Object.class
        }), "expected ByteBuffer, length, mask, and marker parameters");

        ByteBuffer buffer = ByteBuffer.wrap(new byte[] {9, 1, 2, 3, 8});
        buffer.position(1);
        buffer.limit(4);
        Object result = method.invoke(null, buffer, 0, 1, null);
        Class<?> byteStringClass = result.getClass();
        int size = ((Number) byteStringClass.getMethod("getSize").invoke(result)).intValue();
        Method get = byteStringClass.getMethod("get", int.class);
        int first = ((Number) get.invoke(result, 0)).intValue();
        int second = ((Number) get.invoke(result, 1)).intValue();
        int third = ((Number) get.invoke(result, 2)).intValue();
        require(size == 3 && first == 1 && second == 2 && third == 3,
            "mask=1 must default length to ByteBuffer.remaining()");
        require(buffer.position() == 4 && buffer.remaining() == 0,
            "relative getByteString must advance the ByteBuffer position by remaining()");

        System.out.println("method=public static synthetic bridge=false");
        System.out.println("descriptor=" + descriptor);
        System.out.println("default=mask:1 marker:null result:3:1:2:3 position:4 remaining:0");
    }
}
