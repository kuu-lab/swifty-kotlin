import java.lang.reflect.Constructor;
import java.lang.reflect.Modifier;
import kotlinx.io.Segment;
import kotlinx.io.SegmentCopyTracker;

public final class SegmentBridgeProbe {
    public static void main(String[] args) throws Exception {
        Class<?> marker = Class.forName("kotlin.jvm.internal.DefaultConstructorMarker");
        Constructor<Segment> bridge = Segment.class.getDeclaredConstructor(
                byte[].class, int.class, int.class, SegmentCopyTracker.class, boolean.class, marker);
        if (!Modifier.isPublic(bridge.getModifiers()) || !bridge.isSynthetic()) {
            throw new AssertionError("Expected a public synthetic constructor bridge");
        }

        byte[] input = new byte[8192];
        for (int i = 0; i < input.length; i++) input[i] = (byte) i;
        Segment segment = bridge.newInstance(input, 17, 23, null, true, null);
        assertIntField(segment, "pos", 17);
        assertIntField(segment, "limit", 23);
        if (!segment.getOwner()) throw new AssertionError("Owner flag was not initialized");

        Constructor<Segment> emptyBridge = Segment.class.getDeclaredConstructor(marker);
        Segment sink = emptyBridge.newInstance(new Object[] {null});
        segment.writeTo(sink, 6);
        var dataField = Segment.class.getDeclaredField("data");
        dataField.setAccessible(true);
        byte[] copied = (byte[]) dataField.get(sink);
        if (copied[0] != 17 || copied[5] != 22) {
            throw new AssertionError("Segment.writeTo did not copy the requested bytes");
        }

        Constructor<Segment> privateConstructor = Segment.class.getDeclaredConstructor(
                byte[].class, int.class, int.class, SegmentCopyTracker.class, boolean.class);
        if (!Modifier.isPrivate(privateConstructor.getModifiers())) {
            throw new AssertionError("Source constructor lost private visibility");
        }
        System.out.println("public synthetic bridge invoked; private constructor retained; writeTo copied bytes");
    }

    private static void assertIntField(Segment segment, String name, int expected) throws Exception {
        var field = Segment.class.getDeclaredField(name);
        field.setAccessible(true);
        if (field.getInt(segment) != expected) {
            throw new AssertionError("Synthetic bridge did not initialize " + name);
        }
    }
}
