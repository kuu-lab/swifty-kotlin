import java.lang.invoke.MethodType;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.charset.Charset;
import java.util.Arrays;

public final class SinkWriteStringCharsetJvmAbiProbe {
    private static final String TEXT = "təˈranəˌsôr";
    private static final String FULL_HEX =
        "0000007400000259000002c800000072000000610000006e00000259000002cc00000073000000f400000072";
    private static final String START_DEFAULT_HEX =
        "0000007400000259000002c800000072000000610000006e00000259";
    private static final String END_DEFAULT_HEX =
        "00000072000000610000006e00000259000002cc00000073000000f400000072";
    private static final String EXPLICIT_RANGE_HEX = "00000072000000610000006e00000259";

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static Object newBuffer(Class<?> bufferType) throws Exception {
        return bufferType.getConstructor().newInstance();
    }

    private static String readHex(Class<?> bufferType, Object buffer) throws Exception {
        long size = ((Number) bufferType.getMethod("getSize").invoke(buffer)).longValue();
        Method readByte = bufferType.getMethod("readByte");
        char[] digits = "0123456789abcdef".toCharArray();
        StringBuilder result = new StringBuilder(Math.toIntExact(size) * 2);
        for (long index = 0; index < size; index++) {
            int value = ((Number) readByte.invoke(buffer)).intValue() & 0xff;
            result.append(digits[value >>> 4]).append(digits[value & 0x0f]);
        }
        return result.toString();
    }

    private static String invokeDefault(
        Method method, Class<?> bufferType, Charset charset, int startIndex, int endIndex, int mask
    ) throws Exception {
        Object buffer = newBuffer(bufferType);
        method.invoke(null, new Object[] {buffer, TEXT, charset, startIndex, endIndex, mask, null});
        return readHex(bufferType, buffer);
    }

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.SinksJvmKt");
        Class<?> sinkType = Class.forName("kotlinx.io.Sink");
        Class<?> bufferType = Class.forName("kotlinx.io.Buffer");
        String expectedDescriptor =
            "(Lkotlinx/io/Sink;Ljava/lang/String;Ljava/nio/charset/Charset;IIILjava/lang/Object;)V";
        Method[] matches = Arrays.stream(owner.getDeclaredMethods())
            .filter(method -> method.getName().equals("writeString$default"))
            .filter(method -> MethodType.methodType(method.getReturnType(), method.getParameterTypes())
                .toMethodDescriptorString().equals(expectedDescriptor))
            .toArray(Method[]::new);
        require(matches.length == 1, "expected one writeString$default method with the target descriptor");

        Method method = matches[0];
        String descriptor = MethodType.methodType(method.getReturnType(), method.getParameterTypes())
            .toMethodDescriptorString();
        require(descriptor.equals(expectedDescriptor), "descriptor: " + descriptor);
        require(Modifier.isPublic(method.getModifiers()), "method must be public");
        require(Modifier.isStatic(method.getModifiers()), "method must be static");
        require(method.isSynthetic(), "method must be synthetic");
        require(!method.isBridge(), "method must not carry ACC_BRIDGE");
        require(method.getReturnType() == void.class, "method must return void");
        require(Arrays.equals(method.getParameterTypes(), new Class<?>[] {
            sinkType, String.class, Charset.class, int.class, int.class, int.class, Object.class
        }), "expected Sink, String, Charset, start, end, mask, and marker parameters");

        Charset charset = Charset.forName("UTF-32BE");
        String full = invokeDefault(method, bufferType, charset, 99, 99, 12);
        String startDefault = invokeDefault(method, bufferType, charset, 99, 7, 4);
        String endDefault = invokeDefault(method, bufferType, charset, 3, -1, 8);
        String explicitRange = invokeDefault(method, bufferType, charset, 3, 7, 0);
        require(full.equals(FULL_HEX), "mask 0x0c must default both range indices: " + full);
        require(startDefault.equals(START_DEFAULT_HEX), "mask 0x04 must default startIndex: " + startDefault);
        require(endDefault.equals(END_DEFAULT_HEX), "mask 0x08 must default endIndex: " + endDefault);
        require(explicitRange.equals(EXPLICIT_RANGE_HEX), "explicit range bytes: " + explicitRange);

        System.out.println("method=public static synthetic bridge=false");
        System.out.println("descriptor=" + descriptor);
        System.out.println("mask=startIndex:0x04,endIndex:0x08,marker=java.lang.Object");
        System.out.println("both-defaults=" + full);
        System.out.println("start-default=" + startDefault);
        System.out.println("end-default=" + endDefault);
        System.out.println("explicit-range=" + explicitRange);
    }
}
