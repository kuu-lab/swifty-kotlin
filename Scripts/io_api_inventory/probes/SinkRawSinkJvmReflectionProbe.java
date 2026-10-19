import java.io.Flushable;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Set;
import java.util.TreeSet;

public final class SinkRawSinkJvmReflectionProbe {
    // IO_API_VALIDATION_PROBE: probe:KUU-2612:sink-rawsink-jvm-declarations

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static Set<Class<?>> interfacesOf(Class<?> type) {
        return Set.of(type.getInterfaces());
    }

    private static String signature(Method method) {
        String parameters = Arrays.stream(method.getParameterTypes())
                .map(Class::getName)
                .reduce((left, right) -> left + "," + right)
                .orElse("");
        return method.getName() + "(" + parameters + ")";
    }

    private static Set<String> signatures(Class<?> type) {
        Set<String> result = new TreeSet<>();
        for (Method method : type.getDeclaredMethods()) {
            require(Modifier.isPublic(method.getModifiers()), type.getName() + " has a non-public method: " + method);
            require(Modifier.isAbstract(method.getModifiers()), type.getName() + " has a concrete method: " + method);
            result.add(signature(method));
        }
        return result;
    }

    public static void main(String[] args) throws Exception {
        Class<?> sink = Class.forName("kotlinx.io.Sink");
        Class<?> rawSink = Class.forName("kotlinx.io.RawSink");
        Class<?> buffer = Class.forName("kotlinx.io.Buffer");

        require(sink.isInterface() && Modifier.isPublic(sink.getModifiers()), "Sink visibility/kind mismatch");
        require(rawSink.isInterface() && Modifier.isPublic(rawSink.getModifiers()), "RawSink visibility/kind mismatch");
        require(interfacesOf(sink).equals(Set.of(rawSink)), "Sink direct supertype mismatch: " + interfacesOf(sink));
        require(interfacesOf(rawSink).equals(Set.of(AutoCloseable.class, Flushable.class)),
                "RawSink JVM actual supertypes mismatch: " + interfacesOf(rawSink));

        Method sinkFlush = sink.getDeclaredMethod("flush");
        require(Modifier.isPublic(sinkFlush.getModifiers()) && Modifier.isAbstract(sinkFlush.getModifiers()),
                "Sink.flush must be a public abstract declaration");
        Set<String> rawMethods = signatures(rawSink);
        require(rawMethods.equals(Set.of("close()", "flush()", "write(kotlinx.io.Buffer,long)")),
                "RawSink method set mismatch: " + rawMethods);
        rawSink.getDeclaredMethod("write", buffer, long.class);
        rawSink.getDeclaredMethod("flush");
        rawSink.getDeclaredMethod("close");

        System.out.println("Sink=public-interface");
        System.out.println("Sink.interfaces=kotlinx.io.RawSink");
        System.out.println("Sink.flush=public-abstract");
        System.out.println("RawSink=public-interface");
        System.out.println("RawSink.interfaces=java.io.Flushable,java.lang.AutoCloseable");
        System.out.println("RawSink.methods=close(),flush(),write(kotlinx.io.Buffer,long)");
    }
}
