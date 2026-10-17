import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class SegmentPosAbiProbe {
    public static void main(String[] args) throws Exception {
        Class<?> segmentClass = Class.forName("kotlinx.io.Segment");
        Method getter = segmentClass.getDeclaredMethod("getPos");
        Method setter = segmentClass.getDeclaredMethod("setPos", int.class);

        requireAccessor(getter, int.class, new Class<?>[0]);
        requireAccessor(setter, void.class, new Class<?>[] {int.class});

        System.out.println("getPos()I=public-final-synthetic");
        System.out.println("setPos(I)V=public-final-synthetic");
    }

    private static void requireAccessor(Method method, Class<?> returnType, Class<?>[] parameterTypes) {
        int modifiers = method.getModifiers();
        if (method.getReturnType() != returnType
                || !java.util.Arrays.equals(method.getParameterTypes(), parameterTypes)
                || !Modifier.isPublic(modifiers)
                || !Modifier.isFinal(modifiers)
                || Modifier.isStatic(modifiers)
                || !method.isSynthetic()) {
            throw new AssertionError("unexpected Segment.pos JVM accessor ABI: " + method);
        }
    }
}
