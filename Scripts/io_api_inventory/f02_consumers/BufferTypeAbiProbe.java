import java.lang.reflect.Constructor;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.Set;
import kotlinx.io.Buffer;
import kotlinx.io.Sink;
import kotlinx.io.Source;

public final class BufferTypeAbiProbe {
    public static void main(String[] args) throws ReflectiveOperationException {
        Class<Buffer> type = Buffer.class;
        require(type.getName().equals("kotlinx.io.Buffer"), "binary name");

        int modifiers = type.getModifiers();
        require(Modifier.isPublic(modifiers), "public class");
        require(Modifier.isFinal(modifiers), "final class");
        require(!Modifier.isAbstract(modifiers), "concrete class");

        Set<Class<?>> interfaces = Set.copyOf(Arrays.asList(type.getInterfaces()));
        require(interfaces.equals(Set.of(Sink.class, Source.class)), "exact direct interfaces");

        Constructor<?>[] constructors = type.getDeclaredConstructors();
        require(constructors.length == 1, "one declared constructor");
        Constructor<Buffer> constructor = type.getDeclaredConstructor();
        require(Modifier.isPublic(constructor.getModifiers()), "public no-argument constructor");
        require(constructor.getParameterCount() == 0, "no constructor parameters");

        Buffer instance = constructor.newInstance();
        require(instance.getSize() == 0L, "empty initial state");
        System.out.println("BUFFER-ABI:PASS");
    }

    private static void require(boolean condition, String contract) {
        if (!condition) {
            throw new AssertionError("Buffer ABI mismatch: " + contract);
        }
    }
}
