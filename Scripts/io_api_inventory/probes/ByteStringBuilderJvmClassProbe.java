import java.lang.reflect.Modifier;

public final class ByteStringBuilderJvmClassProbe {
    public static void main(String[] args) throws Exception {
        Class<?> builder = Class.forName("kotlinx.io.bytestring.ByteStringBuilder");
        int modifiers = builder.getModifiers();
        if (!Modifier.isPublic(modifiers)) {
            throw new AssertionError("ByteStringBuilder is not public");
        }
        if (!Modifier.isFinal(modifiers)) {
            throw new AssertionError("ByteStringBuilder is not final");
        }
        if (builder.isInterface() || Modifier.isAbstract(modifiers)) {
            throw new AssertionError("ByteStringBuilder must be a concrete class");
        }
        if (builder.getSuperclass() != Object.class) {
            throw new AssertionError("Unexpected JVM superclass: " + builder.getSuperclass());
        }
        System.out.println("BYTESTRINGBUILDER_JVM_CLASS_SHAPE_PASS");
    }
}
