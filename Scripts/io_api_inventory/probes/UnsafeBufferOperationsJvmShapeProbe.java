import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

public final class UnsafeBufferOperationsJvmShapeProbe {
    private static final String CLASS_NAME = "kotlinx.io.unsafe.UnsafeBufferOperations";

    public static void main(String[] args) throws Exception {
        Class<?> owner = Class.forName(CLASS_NAME);
        int classModifiers = owner.getModifiers();
        require(Modifier.isPublic(classModifiers), "class is public");
        require(Modifier.isFinal(classModifiers), "class is final");
        require(!owner.isInterface(), "class is not an interface");

        Field instance = owner.getDeclaredField("INSTANCE");
        int fieldModifiers = instance.getModifiers();
        require(instance.getDeclaringClass() == owner, "INSTANCE owner is exact");
        require(instance.getType() == owner, "INSTANCE descriptor is exact");
        require(Modifier.isPublic(fieldModifiers), "INSTANCE is public");
        require(Modifier.isStatic(fieldModifiers), "INSTANCE is static");
        require(Modifier.isFinal(fieldModifiers), "INSTANCE is final");
        require(instance.get(null) == instance.get(null), "INSTANCE identity is stable");

        System.out.println("PASS:public-final-class;INSTANCE=public-static-final:self;identity=shared");
    }

    private static void require(boolean condition, String contract) {
        if (!condition) {
            throw new AssertionError(contract);
        }
    }
}
