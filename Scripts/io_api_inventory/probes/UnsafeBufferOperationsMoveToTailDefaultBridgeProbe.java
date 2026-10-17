import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Probe the pinned kotlinx-io JVM bridge directly through reflection. */
public final class UnsafeBufferOperationsMoveToTailDefaultBridgeProbe {
    private static final String ROW_ID = "jvm-8178a8b4ccb3fdd8";
    private static final String OWNER_NAME = "kotlinx.io.unsafe.UnsafeBufferOperations";
    private static final String BRIDGE_NAME = "moveToTail$default";
    private static int assertionCount;

    private UnsafeBufferOperationsMoveToTailDefaultBridgeProbe() {}

    private static void require(boolean condition, String message) {
        assertionCount++;
        if (!condition) throw new AssertionError(message);
    }

    private static String descriptor(Class<?> type) {
        if (type.isArray()) return type.getName().replace('.', '/');
        if (!type.isPrimitive()) return "L" + type.getName().replace('.', '/') + ";";
        if (type == void.class) return "V";
        if (type == boolean.class) return "Z";
        if (type == byte.class) return "B";
        if (type == char.class) return "C";
        if (type == short.class) return "S";
        if (type == int.class) return "I";
        if (type == long.class) return "J";
        if (type == float.class) return "F";
        if (type == double.class) return "D";
        throw new IllegalArgumentException("unsupported JVM type: " + type);
    }

    private static String descriptor(Method method) {
        StringBuilder result = new StringBuilder("(");
        for (Class<?> parameter : method.getParameterTypes()) result.append(descriptor(parameter));
        return result.append(')').append(descriptor(method.getReturnType())).toString();
    }

    private static List<String> modifiers(Method method) {
        List<String> result = new ArrayList<>();
        int flags = method.getModifiers();
        if (Modifier.isPublic(flags)) result.add("public");
        if (Modifier.isProtected(flags)) result.add("protected");
        if (Modifier.isPrivate(flags)) result.add("private");
        if (Modifier.isStatic(flags)) result.add("static");
        if (Modifier.isFinal(flags)) result.add("final");
        if (Modifier.isAbstract(flags)) result.add("abstract");
        if (method.isBridge()) result.add("bridge");
        if (method.isSynthetic()) result.add("synthetic");
        return result;
    }

    private static List<Integer> boxed(byte[] bytes) {
        List<Integer> result = new ArrayList<>();
        for (byte value : bytes) result.add(Byte.toUnsignedInt(value));
        return result;
    }

    private static Map<String, Object> shape(Method method) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("owner", method.getDeclaringClass().getName());
        result.put("name", method.getName());
        result.put("descriptor", descriptor(method));
        result.put("modifiers", modifiers(method));
        result.put("parameterTypes", Arrays.stream(method.getParameterTypes()).map(Class::getName).toList());
        result.put("returnType", method.getReturnType().getName());
        return result;
    }

    private static Object newBuffer(Class<?> bufferType) throws ReflectiveOperationException {
        return bufferType.getConstructor().newInstance();
    }

    private static Map<String, Object> invokeRange(Method bridge, Method readByteArray, Object receiver,
                                                    Class<?> bufferType, String name, byte[] bytes,
                                                    int startArgument, int endArgument, int mask,
                                                    byte[] expected) throws ReflectiveOperationException {
        Object buffer = newBuffer(bufferType);
        bridge.invoke(null, receiver, buffer, bytes, startArgument, endArgument, mask, null);
        byte[] actual = (byte[]) readByteArray.invoke(null, buffer);
        require(Arrays.equals(actual, expected), name + " produced " + Arrays.toString(actual));
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("name", name);
        result.put("mask", mask);
        result.put("input", boxed(bytes));
        result.put("startArgument", startArgument);
        result.put("endArgument", endArgument);
        result.put("result", boxed(actual));
        return result;
    }

    private static Map<String, Object> invokeFailure(Method bridge, Object receiver, Class<?> bufferType,
                                                      String name, byte[] bytes, int startArgument,
                                                      int endArgument, int mask, String expectedType)
            throws ReflectiveOperationException {
        String actualType = "none";
        try {
            bridge.invoke(null, receiver, newBuffer(bufferType), bytes, startArgument, endArgument, mask, null);
        } catch (InvocationTargetException failure) {
            actualType = failure.getCause().getClass().getName();
        }
        require(expectedType.equals(actualType), name + " threw " + actualType);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("name", name);
        result.put("mask", mask);
        result.put("input", boxed(bytes));
        result.put("startArgument", startArgument);
        result.put("endArgument", endArgument);
        result.put("exception", actualType);
        return result;
    }

    private static String json(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean || value instanceof Number) return value.toString();
        if (value instanceof Map<?, ?> map) {
            List<String> fields = new ArrayList<>();
            map.forEach((key, item) -> fields.add(json(key.toString()) + ":" + json(item)));
            return "{" + String.join(",", fields) + "}";
        }
        if (value instanceof Iterable<?> items) {
            List<String> fields = new ArrayList<>();
            items.forEach(item -> fields.add(json(item)));
            return "[" + String.join(",", fields) + "]";
        }
        StringBuilder result = new StringBuilder("\"");
        value.toString().codePoints().forEach(character -> {
            switch (character) {
                case '"' -> result.append("\\\"");
                case '\\' -> result.append("\\\\");
                case '\n' -> result.append("\\n");
                case '\r' -> result.append("\\r");
                case '\t' -> result.append("\\t");
                default -> {
                    if (character < 32) result.append(String.format("\\u%04x", character));
                    else result.appendCodePoint(character);
                }
            }
        });
        return result.append('"').toString();
    }

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName(OWNER_NAME);
        Class<?> bufferType = Class.forName("kotlinx.io.Buffer");
        Field instanceField = owner.getDeclaredField("INSTANCE");
        require(instanceField.getType() == owner, "INSTANCE field type changed");
        require(Modifier.isPublic(instanceField.getModifiers()), "INSTANCE field is not public");
        require(Modifier.isStatic(instanceField.getModifiers()), "INSTANCE field is not static");
        require(Modifier.isFinal(instanceField.getModifiers()), "INSTANCE field is not final");
        Object receiver = instanceField.get(null);
        require(receiver != null && receiver.getClass() == owner, "INSTANCE receiver type changed");

        Method bridge = owner.getDeclaredMethod(BRIDGE_NAME, owner, bufferType, byte[].class,
                int.class, int.class, int.class, Object.class);
        require(Arrays.equals(bridge.getParameterTypes(), new Class<?>[] {
                owner, bufferType, byte[].class, int.class, int.class, int.class, Object.class
        }), "bridge parameter types changed");
        require(bridge.getReturnType() == void.class, "bridge return type changed");
        require(Modifier.isPublic(bridge.getModifiers()), "bridge is not public");
        require(Modifier.isStatic(bridge.getModifiers()), "bridge is not static");
        require(bridge.isSynthetic(), "bridge is not synthetic");
        require(!bridge.isBridge(), "synthetic default bridge became a JVM bridge");
        require(descriptor(bridge).equals(
                "(Lkotlinx/io/unsafe/UnsafeBufferOperations;Lkotlinx/io/Buffer;[BIIILjava/lang/Object;)V"),
                "bridge descriptor changed: " + descriptor(bridge));

        Method regular = owner.getDeclaredMethod("moveToTail", bufferType,
                byte[].class, int.class, int.class);
        require(regular.getReturnType() == void.class, "underlying return type changed");
        require(Modifier.isPublic(regular.getModifiers()), "underlying member is not public");
        require(Modifier.isFinal(regular.getModifiers()), "underlying member is not final");
        require(!Modifier.isStatic(regular.getModifiers()), "underlying member became static");
        require(!regular.isSynthetic(), "underlying member became synthetic");
        require(descriptor(regular).equals("(Lkotlinx/io/Buffer;[BII)V"),
                "underlying descriptor changed: " + descriptor(regular));

        Method readByteArray = Class.forName("kotlinx.io.SourcesKt")
                .getMethod("readByteArray", Class.forName("kotlinx.io.Source"));

        List<Map<String, Object>> observations = new ArrayList<>();
        byte[] bytes = new byte[] {1, 2, 3, 4};
        observations.add(invokeRange(bridge, readByteArray, receiver, bufferType,
                "all-defaults", bytes, 91, 92, 12, new byte[] {1, 2, 3, 4}));
        observations.add(invokeRange(bridge, readByteArray, receiver, bufferType,
                "default-start", bytes, 91, 3, 4, new byte[] {1, 2, 3}));
        observations.add(invokeRange(bridge, readByteArray, receiver, bufferType,
                "default-end", bytes, 2, 92, 8, new byte[] {3, 4}));
        observations.add(invokeRange(bridge, readByteArray, receiver, bufferType,
                "explicit-range", bytes, 1, 3, 0, new byte[] {2, 3}));
        observations.add(invokeRange(bridge, readByteArray, receiver, bufferType,
                "empty-default-end", new byte[] {1, 2, 3}, 3, 92, 8, new byte[] {}));
        observations.add(invokeFailure(bridge, receiver, bufferType,
                "default-start-oob", bytes, 91, 5, 4, "java.lang.IndexOutOfBoundsException"));
        observations.add(invokeFailure(bridge, receiver, bufferType,
                "explicit-negative-start", bytes, -1, 1, 0, "java.lang.IndexOutOfBoundsException"));
        observations.add(invokeFailure(bridge, receiver, bufferType,
                "explicit-reversed", bytes, 2, 1, 0, "java.lang.IllegalArgumentException"));

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("row_id", ROW_ID);
        report.put("method_shape", shape(bridge));
        report.put("underlying_shape", shape(regular));
        report.put("default_masks", Map.of("startIndex", 4, "endIndex", 8, "both", 12));
        report.put("observations", observations);
        report.put("assertion_count", assertionCount);
        report.put("result", "PASS");
        System.out.println(json(report));
    }
}
