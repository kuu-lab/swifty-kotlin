import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

public final class SystemFileSystemJvmAbiProbe {
    private SystemFileSystemJvmAbiProbe() {}

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.files.FileSystemJvmKt");
        Class<?> fileSystemType = Class.forName("kotlinx.io.files.FileSystem");
        Field field = owner.getDeclaredField("SystemFileSystem");
        int requiredFlags = Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL;

        require(field.getDeclaringClass() == owner, "field owner");
        require(owner.getField("SystemFileSystem") == field, "public field visibility");
        require(field.getType() == fileSystemType, "field type");
        require((field.getModifiers() & requiredFlags) == requiredFlags, "public static final flags");

        String descriptor = "L" + field.getType().getName().replace('.', '/') + ";";
        require(descriptor.equals("Lkotlinx/io/files/FileSystem;"), "field descriptor");

        Object first = field.get(null);
        Object second = field.get(null);
        require(first != null && fileSystemType.isInstance(first), "field value type");
        require(first == second, "field value identity");

        System.out.println("SystemFileSystemJvmAbiProbe:owner=kotlinx.io.files.FileSystemJvmKt");
        System.out.println("SystemFileSystemJvmAbiProbe:descriptor=" + descriptor);
        System.out.println("SystemFileSystemJvmAbiProbe:flags=" + Modifier.toString(field.getModifiers()));
        System.out.println("SystemFileSystemJvmAbiProbe:value-type=FileSystem");
        System.out.println("SystemFileSystemJvmAbiProbe:identity=stable");
    }

    private static void require(boolean condition, String contract) {
        if (!condition) {
            throw new AssertionError("SystemFileSystem JVM ABI mismatch: " + contract);
        }
    }
}
