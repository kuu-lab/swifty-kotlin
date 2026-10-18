import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class SegmentReadContextAbiProbe {
    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName("kotlinx.io.unsafe.UnsafeBufferOperationsKt");
        Class<?> returnType = Class.forName("kotlinx.io.unsafe.SegmentReadContext");
        Method getter = owner.getDeclaredMethod("getSegmentReadContextImpl");
        int modifiers = getter.getModifiers();

        if (getter.getParameterCount() != 0
                || getter.getReturnType() != returnType
                || !Modifier.isPublic(modifiers)
                || !Modifier.isStatic(modifiers)
                || !Modifier.isFinal(modifiers)
                || !getter.isSynthetic()) {
            throw new AssertionError("unexpected SegmentReadContextImpl JVM getter ABI: " + getter);
        }

        Object first = getter.invoke(null);
        Object second = getter.invoke(null);
        if (first == null || first != second) {
            throw new AssertionError("JVM getter did not return its stable singleton");
        }

        System.out.println(
                "public static final synthetic getSegmentReadContextImpl()"
                        + "Lkotlinx/io/unsafe/SegmentReadContext;;sameInstance=true");
    }
}
