import java.io.FileNotFoundException;
import java.io.IOException;
import java.lang.invoke.MethodType;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.nio.file.Files;
import java.nio.file.Path;

public final class FileSystemDefaultBridgeAbiProbe {
    private static final int DEFAULT_FLAG_MASK = 0x2;

    private static Method bridge(Class<?> owner, String name, Class<?> resultType, String descriptor) throws Exception {
        Method method = owner.getDeclaredMethod(
                name,
                owner,
                Class.forName("kotlinx.io.files.Path"),
                boolean.class,
                int.class,
                Object.class);
        int modifiers = method.getModifiers();
        if (method.getDeclaringClass() != owner
                || method.getReturnType() != resultType
                || !Modifier.isPublic(modifiers)
                || !Modifier.isStatic(modifiers)
                || !method.isSynthetic()
                || method.isBridge()) {
            throw new AssertionError("unexpected JVM default bridge: " + method);
        }
        String actualDescriptor = MethodType.methodType(method.getReturnType(), method.getParameterTypes()).descriptorString();
        if (!actualDescriptor.equals(descriptor)) {
            throw new AssertionError("unexpected JVM method descriptor: " + actualDescriptor + " != " + descriptor);
        }
        return method;
    }

    private static void regularDeclaration(Class<?> owner, String name, Class<?> resultType, String descriptor) throws Exception {
        Method method = owner.getDeclaredMethod(name, Class.forName("kotlinx.io.files.Path"), boolean.class);
        int modifiers = method.getModifiers();
        if (method.getDeclaringClass() != owner
                || method.getReturnType() != resultType
                || !Modifier.isPublic(modifiers)
                || !Modifier.isAbstract(modifiers)) {
            throw new AssertionError("unexpected underlying FileSystem declaration: " + method);
        }
        String actualDescriptor = MethodType.methodType(method.getReturnType(), method.getParameterTypes()).descriptorString();
        if (!actualDescriptor.equals(descriptor)) {
            throw new AssertionError("unexpected regular JVM descriptor: " + actualDescriptor + " != " + descriptor);
        }
    }

    private static Object kioPath(Method factory, Path path) throws Exception {
        return factory.invoke(null, new Object[] {path.toString(), new String[0]});
    }

    private static Throwable invocationFailure(Method method, Object... arguments) throws Exception {
        try {
            method.invoke(null, arguments);
        } catch (InvocationTargetException failure) {
            return failure.getCause();
        }
        throw new AssertionError("expected the default bridge call to fail: " + method.getName());
    }

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.files.FileSystem");
        Class<?> pathType = Class.forName("kotlinx.io.files.Path");
        Class<?> rawSinkType = Class.forName("kotlinx.io.RawSink");
        if (!owner.isInterface()) throw new AssertionError("FileSystem must remain an interface");

        regularDeclaration(owner, "sink", rawSinkType, "(Lkotlinx/io/files/Path;Z)Lkotlinx/io/RawSink;");
        regularDeclaration(owner, "delete", Void.TYPE, "(Lkotlinx/io/files/Path;Z)V");
        regularDeclaration(owner, "createDirectories", Void.TYPE, "(Lkotlinx/io/files/Path;Z)V");
        Method sink = bridge(owner, "sink$default", rawSinkType,
                "(Lkotlinx/io/files/FileSystem;Lkotlinx/io/files/Path;ZILjava/lang/Object;)Lkotlinx/io/RawSink;");
        Method delete = bridge(owner, "delete$default", Void.TYPE,
                "(Lkotlinx/io/files/FileSystem;Lkotlinx/io/files/Path;ZILjava/lang/Object;)V");
        Method createDirectories = bridge(owner, "createDirectories$default", Void.TYPE,
                "(Lkotlinx/io/files/FileSystem;Lkotlinx/io/files/Path;ZILjava/lang/Object;)V");
        for (Method method : new Method[] {sink, delete, createDirectories}) {
            Class<?>[] parameters = method.getParameterTypes();
            if (parameters.length != 5
                    || parameters[0] != owner
                    || parameters[1] != pathType
                    || parameters[2] != boolean.class
                    || parameters[3] != int.class
                    || parameters[4] != Object.class) {
                throw new AssertionError("unexpected receiver/flag/mask/marker shape: " + method);
            }
        }

        Class<?> jvmFileSystem = Class.forName("kotlinx.io.files.FileSystemJvmKt");
        Object fileSystem = jvmFileSystem.getField("SystemFileSystem").get(null);
        Method pathFactory = Class.forName("kotlinx.io.files.PathsKt")
                .getMethod("Path", String.class, String[].class);
        Path root = Files.createTempDirectory("kuu2630-bridge-");
        Path sinkPath = root.resolve("sink");
        Path missingPath = root.resolve("missing");
        Path directoryPath = root.resolve("directory");
        try {
            Files.writeString(sinkPath, "seed");
            Object raw = sink.invoke(
                    null, fileSystem, kioPath(pathFactory, sinkPath), true, DEFAULT_FLAG_MASK, null);
            rawSinkType.getMethod("close").invoke(raw);
            if (!Files.readString(sinkPath).isEmpty()) {
                throw new AssertionError("mask 0x2 did not apply sink append=false");
            }

            Throwable missing = invocationFailure(
                    delete, fileSystem, kioPath(pathFactory, missingPath), false, DEFAULT_FLAG_MASK, null);
            if (!(missing instanceof FileNotFoundException)) {
                throw new AssertionError("mask 0x2 did not apply delete mustExist=true", missing);
            }
            delete.invoke(null, fileSystem, kioPath(pathFactory, missingPath), false, 0, null);

            Files.createDirectory(directoryPath);
            createDirectories.invoke(
                    null, fileSystem, kioPath(pathFactory, directoryPath), true, DEFAULT_FLAG_MASK, null);
            Throwable existingDirectory = invocationFailure(
                    createDirectories, fileSystem, kioPath(pathFactory, directoryPath), true, 0, null);
            if (!(existingDirectory instanceof IOException)) {
                throw new AssertionError("explicit mustCreate=true did not reject the existing directory", existingDirectory);
            }
        } finally {
            Files.deleteIfExists(sinkPath);
            Files.deleteIfExists(directoryPath);
            Files.deleteIfExists(root);
        }

        System.out.println("FileSystem default bridge ABI PASS: owner=kotlinx.io.files.FileSystem");
        System.out.println("methods=3 flags=public,static,synthetic bridge=false mask=0x2 marker=java.lang.Object");
        System.out.println("mask behavior PASS: sink.append=false delete.mustExist=true createDirectories.mustCreate=false");
    }
}
