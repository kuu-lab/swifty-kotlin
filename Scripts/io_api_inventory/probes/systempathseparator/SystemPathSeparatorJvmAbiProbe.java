import java.io.File;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class SystemPathSeparatorJvmAbiProbe {
    private SystemPathSeparatorJvmAbiProbe() {}

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.files.PathsJvmKt");
        Field field = owner.getDeclaredField("SystemPathSeparator");
        int requiredFlags = Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL;

        require(field.getDeclaringClass() == owner, "field owner");
        require(owner.getField("SystemPathSeparator").equals(field), "public field visibility");
        require(field.getType() == char.class, "field type");
        require(field.getModifiers() == requiredFlags, "public static final flags");
        require("C".equals(descriptor(field.getType())), "field descriptor");
        require(field.getChar(null) == File.separatorChar, "field value matches the platform separator");
        for (Method method : owner.getDeclaredMethods()) {
            require(!method.getName().equals("getSystemPathSeparator"), "JvmField getter absence");
        }

        System.out.println("SystemPathSeparatorJvmAbiProbe:owner=kotlinx.io.files.PathsJvmKt");
        System.out.println("SystemPathSeparatorJvmAbiProbe:descriptor=C");
        System.out.println("SystemPathSeparatorJvmAbiProbe:flags=" + Modifier.toString(field.getModifiers()));
        System.out.println("SystemPathSeparatorJvmAbiProbe:type=char");
        System.out.println("SystemPathSeparatorJvmAbiProbe:value=" + field.getChar(null));
        System.out.println("SystemPathSeparatorJvmAbiProbe:getter-absent=true");
    }

    private static String descriptor(Class<?> type) {
        if (type == char.class) return "C";
        if (type == void.class) return "V";
        if (type.isPrimitive()) {
            if (type == boolean.class) return "Z";
            if (type == byte.class) return "B";
            if (type == short.class) return "S";
            if (type == int.class) return "I";
            if (type == long.class) return "J";
            if (type == float.class) return "F";
            if (type == double.class) return "D";
        }
        return type.isArray()
                ? type.getName().replace('.', '/')
                : "L" + type.getName().replace('.', '/') + ";";
    }

    private static void require(boolean condition, String contract) {
        if (!condition) {
            throw new AssertionError("SystemPathSeparator JVM ABI mismatch: " + contract);
        }
    }
}
