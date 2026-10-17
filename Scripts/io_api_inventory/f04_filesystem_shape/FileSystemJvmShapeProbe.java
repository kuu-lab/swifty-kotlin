import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.TreeSet;

public final class FileSystemJvmShapeProbe {
    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static String descriptor(Class<?> type) {
        if (type == void.class) return "V";
        if (type == boolean.class) return "Z";
        if (type == byte.class) return "B";
        if (type == char.class) return "C";
        if (type == short.class) return "S";
        if (type == int.class) return "I";
        if (type == long.class) return "J";
        if (type == float.class) return "F";
        if (type == double.class) return "D";
        if (type.isArray()) return type.getName().replace('.', '/');
        return "L" + type.getName().replace('.', '/') + ";";
    }

    private static String methodDescriptor(Method method) {
        StringBuilder result = new StringBuilder(method.getName()).append('(');
        Arrays.stream(method.getParameterTypes()).map(FileSystemJvmShapeProbe::descriptor)
                .forEach(result::append);
        return result.append(')').append(descriptor(method.getReturnType())).toString();
    }

    public static void main(String[] args) throws Exception {
        Class<?> fileSystem = Class.forName("kotlinx.io.files.FileSystem");
        int modifiers = fileSystem.getModifiers();
        require(fileSystem.isInterface(), "FileSystem must be a JVM interface");
        require(Modifier.isPublic(modifiers), "FileSystem must be public");
        require(Modifier.isAbstract(modifiers), "FileSystem must be abstract");
        boolean javaSealed = fileSystem.isSealed();

        Map<String, String> expected = new HashMap<>();
        expected.put("exists", "(Lkotlinx/io/files/Path;)Z");
        expected.put("delete", "(Lkotlinx/io/files/Path;Z)V");
        expected.put("createDirectories", "(Lkotlinx/io/files/Path;Z)V");
        expected.put("atomicMove", "(Lkotlinx/io/files/Path;Lkotlinx/io/files/Path;)V");
        expected.put("source", "(Lkotlinx/io/files/Path;)Lkotlinx/io/RawSource;");
        expected.put("sink", "(Lkotlinx/io/files/Path;Z)Lkotlinx/io/RawSink;");
        expected.put("metadataOrNull", "(Lkotlinx/io/files/Path;)Lkotlinx/io/files/FileMetadata;");
        expected.put("resolve", "(Lkotlinx/io/files/Path;)Lkotlinx/io/files/Path;");
        expected.put("list", "(Lkotlinx/io/files/Path;)Ljava/util/Collection;");

        TreeSet<String> observed = new TreeSet<>();
        for (Method method : fileSystem.getDeclaredMethods()) {
            if (!Modifier.isAbstract(method.getModifiers())) continue;
            require(Modifier.isPublic(method.getModifiers()), "interface member must be public: " + method);
            observed.add(method.getName() + methodDescriptor(method).substring(method.getName().length()));
        }
        require(observed.equals(new TreeSet<>(expected.keySet().stream()
                        .map(name -> name + expected.get(name)).toList())),
                "unexpected FileSystem JVM abstract members: " + observed);
        System.out.println("FileSystem JVM public abstract interface and 9 member descriptors: ok; java-sealed="
                + javaSealed);
    }
}
