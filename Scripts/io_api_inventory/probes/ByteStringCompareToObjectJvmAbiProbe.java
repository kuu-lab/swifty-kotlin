import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import kotlinx.io.bytestring.ByteString;

public final class ByteStringCompareToObjectJvmAbiProbe {
    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static ByteString bytes(int... values) {
        byte[] data = new byte[values.length];
        for (int index = 0; index < values.length; index++) {
            data[index] = (byte) values[index];
        }
        return new ByteString(data, 0, data.length);
    }

    private static int invoke(Method bridge, ByteString receiver, Object argument) throws Exception {
        return (Integer) bridge.invoke(receiver, new Object[] { argument });
    }

    private static void compare(Method bridge, String name, ByteString left, ByteString right, int expected)
            throws Exception {
        int typed = left.compareTo(right);
        int erased = invoke(bridge, left, right);
        require(typed == expected, name + " typed result: " + typed);
        require(erased == typed, name + " erased result: " + erased);
        System.out.println("compare:" + name + "=" + erased);
    }

    private static void expectCause(Method bridge, ByteString receiver, Object argument,
                                    Class<? extends Throwable> expected, String name) throws Exception {
        try {
            invoke(bridge, receiver, argument);
            throw new AssertionError(name + " did not throw " + expected.getSimpleName());
        } catch (InvocationTargetException failure) {
            Throwable cause = failure.getCause();
            require(expected.isInstance(cause), name + " cause: " + cause.getClass().getName());
            System.out.println("boundary:" + name + "=" + cause.getClass().getSimpleName());
        }
    }

    public static void main(String[] args) throws Exception {
        Class<ByteString> owner = ByteString.class;
        require(Comparable.class.isAssignableFrom(owner), "ByteString does not implement Comparable");
        Method bridge = owner.getDeclaredMethod("compareTo", Object.class);
        Method typed = owner.getDeclaredMethod("compareTo", ByteString.class);
        require(Modifier.isPublic(bridge.getModifiers()), "Object bridge is not public");
        require(bridge.getReturnType() == int.class, "Object bridge return type is not int");
        require(bridge.isBridge(), "Object overload is not marked bridge");
        require(bridge.isSynthetic(), "Object overload is not marked synthetic");
        require(Modifier.isPublic(typed.getModifiers()), "typed overload is not public");
        require(typed.getReturnType() == int.class, "typed overload return type is not int");
        require(!typed.isBridge(), "typed overload is unexpectedly marked bridge");
        require(!typed.isSynthetic(), "typed overload is unexpectedly marked synthetic");
        System.out.println("assignable:Comparable=true");
        System.out.println("bridge:public=true:bridge=true:synthetic=true:parameter=Object:return=int");
        System.out.println("typed:public=true:bridge=false:synthetic=false:parameter=ByteString:return=int");

        compare(bridge, "empty", bytes(), bytes(), 0);
        compare(bridge, "equal", bytes(1, 2, 3), bytes(1, 2, 3), 0);
        compare(bridge, "prefix", bytes(1, 2), bytes(1, 2, 3), -1);
        compare(bridge, "lexicographic", bytes(0, 1, 2), bytes(0, 1, 3), -1);
        compare(bridge, "longer", bytes(1, 2, 3), bytes(1, 2), 1);
        compare(bridge, "first-byte", bytes(1, 2, 3), bytes(0, 1, 2), 1);
        compare(bridge, "unsigned-high", bytes(0xff), bytes(0), 1);
        compare(bridge, "unsigned-low", bytes(1), bytes(0x81), -1);

        expectCause(bridge, bytes(1), "not-a-ByteString", ClassCastException.class, "wrong-type");
        expectCause(bridge, bytes(1), null, NullPointerException.class, "null");
    }
}
