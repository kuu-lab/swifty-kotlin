import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;

public final class SourceRawSourceJvmShapeProbe {
    public static void main(String[] args) throws Exception {
        Class<?> rawSource = Class.forName("kotlinx.io.RawSource");
        Class<?> source = Class.forName("kotlinx.io.Source");
        Class<?> buffer = Class.forName("kotlinx.io.Buffer");

        requirePublicAbstractInterface(rawSource, "RawSource");
        requirePublicAbstractInterface(source, "Source");
        require(directInterfaces(rawSource).equals(Set.of(AutoCloseable.class)),
                "RawSource must directly extend java.lang.AutoCloseable: " + directInterfaces(rawSource));
        require(directInterfaces(source).equals(Set.of(rawSource)),
                "Source must directly extend RawSource: " + directInterfaces(source));

        Method close = rawSource.getDeclaredMethod("close");
        require(close.getReturnType() == void.class && Modifier.isAbstract(close.getModifiers()),
                "RawSource must declare abstract close(): void");
        Method read = rawSource.getDeclaredMethod("readAtMostTo", buffer, long.class);
        require(read.getReturnType() == long.class && Modifier.isAbstract(read.getModifiers()),
                "RawSource must declare abstract readAtMostTo(Buffer, long): long");
        require(source.getMethod("close").getDeclaringClass() == rawSource,
                "Source must inherit close() from RawSource");
        require(source.getMethod("readAtMostTo", buffer, long.class).getDeclaringClass() == rawSource,
                "Source must inherit readAtMostTo(Buffer, long) from RawSource");

        System.out.println("{\"result\":\"PASS\",\"source\":\"public abstract interface -> RawSource\","
                + "\"rawSource\":\"public abstract interface -> java.lang.AutoCloseable\","
                + "\"inherited\":[\"close()\",\"readAtMostTo(Buffer,long)\"]}");
    }

    private static void requirePublicAbstractInterface(Class<?> type, String name) {
        int modifiers = type.getModifiers();
        require(type.isInterface() && Modifier.isPublic(modifiers) && Modifier.isAbstract(modifiers),
                name + " must be a public abstract interface");
    }

    private static Set<Class<?>> directInterfaces(Class<?> type) {
        return Arrays.stream(type.getInterfaces()).collect(Collectors.toSet());
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
