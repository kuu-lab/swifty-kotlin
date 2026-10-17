import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

public final class PathJvmAbiProbe {
    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static void main(String[] args) throws Exception {
        Class<?> path = Class.forName("kotlinx.io.files.Path");
        require(Modifier.isFinal(path.getModifiers()), "Path must be a final JVM class");
        require(path.getDeclaredMethod("getParent").getReturnType() == path,
                "Path.parent JVM descriptor must return Path");

        Class<?> jvmFacade = Class.forName("kotlinx.io.files.PathsJvmKt");
        Method stringFactory = jvmFacade.getDeclaredMethod("Path", String.class);
        require(Modifier.isPublic(stringFactory.getModifiers())
                && Modifier.isStatic(stringFactory.getModifiers())
                && stringFactory.getReturnType() == path,
                "Path(String) JVM factory descriptor must be public static");

        Class<?> commonFacade = Class.forName("kotlinx.io.files.PathsKt");
        Method stringPartsFactory = commonFacade.getDeclaredMethod("Path", String.class, String[].class);
        Method pathPartsFactory = commonFacade.getDeclaredMethod("Path", path, String[].class);
        require(Modifier.isPublic(stringPartsFactory.getModifiers())
                && Modifier.isStatic(stringPartsFactory.getModifiers())
                && stringPartsFactory.isVarArgs()
                && stringPartsFactory.getReturnType() == path,
                "Path(String, vararg String) JVM factory descriptor must be public static vararg");
        require(Modifier.isPublic(pathPartsFactory.getModifiers())
                && Modifier.isStatic(pathPartsFactory.getModifiers())
                && pathPartsFactory.isVarArgs()
                && pathPartsFactory.getReturnType() == path,
                "Path(Path, vararg String) JVM factory descriptor must be public static vararg");

        System.out.println("PATH_JVM_PUBLIC_SHAPE_OK");
    }
}
