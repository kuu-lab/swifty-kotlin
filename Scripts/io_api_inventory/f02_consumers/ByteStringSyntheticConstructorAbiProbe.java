import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.Modifier;
import java.net.URISyntaxException;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.jar.JarFile;

public final class ByteStringSyntheticConstructorAbiProbe {
    private static final int ACC_PUBLIC = 0x0001;
    private static final int ACC_STATIC = 0x0008;
    private static final int ACC_BRIDGE = 0x0040;
    private static final int ACC_SYNTHETIC = 0x1000;
    private static final String MARKER = "Lkotlin/jvm/internal/DefaultConstructorMarker;";
    private static final String PRIVATE_PRIMARY = "([BLjava/lang/Object;" + MARKER + ")V";
    private static final String DEFAULTS = "([BIII" + MARKER + ")V";

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("expected the pinned kotlinx-io-bytestring JVM JAR path");
        }
        Path referenceJar = Path.of(args[0]).toRealPath();
        Class<?> owner = Class.forName("kotlinx.io.bytestring.ByteString");
        verifyClassOrigin(owner, referenceJar);

        Map<String, Integer> constructors;
        try (JarFile archive = new JarFile(referenceJar.toFile())) {
            var entry = archive.getJarEntry("kotlinx/io/bytestring/ByteString.class");
            if (entry == null) {
                throw new AssertionError("ByteString class is absent from the pinned reference JAR");
            }
            try (var input = archive.getInputStream(entry)) {
                constructors = constructorFlags(input.readAllBytes());
            }
        }

        requireSyntheticPublicConstructor(constructors, PRIVATE_PRIMARY);
        requireSyntheticPublicConstructor(constructors, DEFAULTS);

        Class<?> marker = Class.forName("kotlin.jvm.internal.DefaultConstructorMarker");
        Constructor<?> privatePrimaryBridge = owner.getDeclaredConstructor(byte[].class, Object.class, marker);
        Constructor<?> defaultsBridge = owner.getDeclaredConstructor(
                byte[].class, int.class, int.class, int.class, marker);
        requireReflectionFlags(privatePrimaryBridge);
        requireReflectionFlags(defaultsBridge);

        byte[] source = {7, 8, 9};
        Object wrapped = privatePrimaryBridge.newInstance(source, new Object(), null);
        requireBytes(owner, wrapped, new byte[] {7, 8, 9});
        requireBytes(owner, defaultsBridge.newInstance(source, 99, 99, 6, null), source);
        requireBytes(owner, defaultsBridge.newInstance(source, 1, 99, 4, null), new byte[] {8, 9});
        requireBytes(owner, defaultsBridge.newInstance(source, 99, 2, 2, null), new byte[] {7, 8});

        System.out.println("PASS descriptors=2 flags=public+synthetic static=false bridge=false masks=2,4,6");
    }

    private static void verifyClassOrigin(Class<?> owner, Path referenceJar)
            throws IOException, URISyntaxException {
        Path actual = Path.of(owner.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
        if (!actual.equals(referenceJar)) {
            throw new AssertionError("ByteString loaded from " + actual + ", expected " + referenceJar);
        }
    }

    private static Map<String, Integer> constructorFlags(byte[] bytes) throws Exception {
        try (DataInputStream input = new DataInputStream(new ByteArrayInputStream(bytes))) {
            if (input.readInt() != 0xCAFEBABE) {
                throw new AssertionError("invalid ByteString classfile magic");
            }
            input.readUnsignedShort();
            input.readUnsignedShort();
            int constantPoolCount = input.readUnsignedShort();
            Object[] constantPool = new Object[constantPoolCount];
            for (int index = 1; index < constantPoolCount; index++) {
                int tag = input.readUnsignedByte();
                switch (tag) {
                    case 1 -> constantPool[index] = input.readUTF();
                    case 3, 4 -> input.readInt();
                    case 5, 6 -> {
                        input.readLong();
                        index++;
                    }
                    case 7, 8, 16, 19, 20 -> input.readUnsignedShort();
                    case 9, 10, 11, 12, 17, 18 -> input.readInt();
                    case 15 -> {
                        input.readUnsignedByte();
                        input.readUnsignedShort();
                    }
                    default -> throw new AssertionError("unsupported constant-pool tag " + tag);
                }
            }

            input.readUnsignedShort();
            input.readUnsignedShort();
            input.readUnsignedShort();
            int interfaceCount = input.readUnsignedShort();
            for (int index = 0; index < interfaceCount; index++) {
                input.readUnsignedShort();
            }
            skipMembers(input, input.readUnsignedShort());

            Map<String, Integer> constructors = new HashMap<>();
            int methodCount = input.readUnsignedShort();
            for (int index = 0; index < methodCount; index++) {
                int access = input.readUnsignedShort();
                String name = (String) constantPool[input.readUnsignedShort()];
                String descriptor = (String) constantPool[input.readUnsignedShort()];
                skipAttributes(input);
                if ("<init>".equals(name)) {
                    constructors.put(descriptor, access);
                }
            }
            return constructors;
        }
    }

    private static void skipMembers(DataInputStream input, int count) throws Exception {
        for (int index = 0; index < count; index++) {
            input.readUnsignedShort();
            input.readUnsignedShort();
            input.readUnsignedShort();
            skipAttributes(input);
        }
    }

    private static void skipAttributes(DataInputStream input) throws Exception {
        int count = input.readUnsignedShort();
        for (int index = 0; index < count; index++) {
            input.readUnsignedShort();
            long length = Integer.toUnsignedLong(input.readInt());
            input.skipNBytes(length);
        }
    }

    private static void requireSyntheticPublicConstructor(Map<String, Integer> constructors, String descriptor) {
        Integer flags = constructors.get(descriptor);
        if (flags == null
                || flags != (ACC_PUBLIC | ACC_SYNTHETIC)
                || (flags & (ACC_STATIC | ACC_BRIDGE)) != 0) {
            throw new AssertionError("unexpected classfile flags for <init> " + descriptor + ": " + flags);
        }
    }

    private static void requireReflectionFlags(Constructor<?> constructor) {
        int modifiers = constructor.getModifiers();
        if (!Modifier.isPublic(modifiers) || Modifier.isStatic(modifiers) || !constructor.isSynthetic()) {
            throw new AssertionError("unexpected reflection flags for " + constructor);
        }
    }

    private static void requireBytes(Class<?> owner, Object instance, byte[] expected) throws Exception {
        var size = owner.getMethod("getSize");
        var get = owner.getMethod("get", int.class);
        if ((int) size.invoke(instance) != expected.length) {
            throw new AssertionError("unexpected ByteString size");
        }
        byte[] actual = new byte[expected.length];
        for (int index = 0; index < actual.length; index++) {
            actual[index] = (Byte) get.invoke(instance, index);
        }
        if (!Arrays.equals(actual, expected)) {
            throw new AssertionError("unexpected bytes: " + Arrays.toString(actual));
        }
    }
}
