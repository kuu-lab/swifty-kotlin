import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

public final class SystemTemporaryDirectoryJvmProbe {
    private static final String OWNER = "kotlinx.io.files.FileSystemJvmKt";
    private static final String FIELD = "SystemTemporaryDirectory";
    private static final String DESCRIPTOR = "Lkotlinx/io/files/Path;";
    private static final String PATH_TYPE = "kotlinx.io.files.Path";

    private SystemTemporaryDirectoryJvmProbe() {}

    public static void main(String[] arguments) throws Exception {
        Class<?> owner = Class.forName(OWNER);
        Class<?> pathType = Class.forName(PATH_TYPE);
        Field field = owner.getField(FIELD);
        int modifiers = field.getModifiers();

        require(field.getDeclaringClass() == owner, "field owner");
        require(field.getType() == pathType, "field descriptor/type");
        require(Modifier.isPublic(modifiers), "public field");
        require(Modifier.isStatic(modifiers), "static field");
        require(Modifier.isFinal(modifiers), "final field");

        Object first = field.get(null);
        Object second = field.get(null);
        require(pathType.isInstance(first), "runtime field value type");
        require(first == second, "static field identity");

        String actualPath = first.toString();
        String expectedPath = trimTrailingSeparators(System.getProperty("java.io.tmpdir"));
        require(actualPath.equals(expectedPath), "java.io.tmpdir value");

        System.out.println("JVM_OWNER:" + field.getDeclaringClass().getName());
        System.out.println("JVM_FIELD:" + field.getName());
        System.out.println("JVM_DESCRIPTOR:" + DESCRIPTOR);
        System.out.println("JVM_FLAGS:public,static,final");
        System.out.println("JVM_VALUE_TYPE:" + first.getClass().getName());
        System.out.println("JVM_VALUE:" + actualPath);
        System.out.println("JVM_VALUE_MATCHES_PROPERTY:true");
        System.out.println("JVM_SAME_INSTANCE:true");
    }

    private static String trimTrailingSeparators(String value) {
        while (value.length() > 1 && value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        return value;
    }

    private static void require(boolean condition, String assertion) {
        if (!condition) {
            throw new AssertionError("SystemTemporaryDirectory JVM probe failed: " + assertion);
        }
    }
}
