#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jdkClassAndClassLoaderResolveResourceURLs() throws {
        try withWorkspace { root in
            let fixture = """
            package dep;
            import java.io.InputStream;
            import java.nio.file.Files;
            import java.nio.file.Path;
            import java.nio.file.Paths;

            public final class Resources {
                public static void main(String[] names) throws Exception {
                    if (names.length == 0) {
                        checkResource("marker.txt");
                        checkResource("absent.txt");
                        return;
                    }
                    for (String name : names) {
                        String resource = name + ".class";
                        Path target = Paths.get("jdk-classes", resource);
                        Files.createDirectories(target.getParent());
                        try (InputStream stream = ClassLoader.getSystemResourceAsStream(resource)) {
                            Files.copy(stream, target);
                        }
                    }
                }

                private static void checkResource(String name) throws Exception {
                    Class<?> owner = Resources.class;
                    Class<?> kotlin = Class.forName("HelloKt");
                    String byClass = (String) kotlin.getMethod("resource", Class.class, String.class)
                        .invoke(null, owner, "/" + name);
                    String byLoader = (String) kotlin.getMethod("resource", ClassLoader.class, String.class)
                        .invoke(null, owner.getClassLoader(), name);
                    System.out.println(byClass == null ? null : byClass.endsWith("/" + name));
                    System.out.println(byLoader == null ? null : byLoader.endsWith("/" + name));
                }
            }
            """
            try fixture.write(to: root.appendingPathComponent("Resources.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Resources.java"], root: root)
            _ = try jvmTool("java", [
                "-cp", "deps", "dep.Resources", "java/lang/Class", "java/lang/ClassLoader", "java/net/URL",
            ], root: root)

            let dependency = root.appendingPathComponent("deps")
            try "content".write(to: dependency.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
            let source = """
            fun <T> Class<T>.resource(name: String): String? = getResource(name)?.toExternalForm()
            fun ClassLoader.resource(name: String): String? = getResource(name)?.toExternalForm()
            """
            let classpath = root.appendingPathComponent("jdk-classes").path
            let result = try compile(source, root: root, mode: .jvmJar, classpath: [classpath])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-cp", artifact + ":" + dependency.path, "dep.Resources"])
            #expect(execution.stdout == "true\ntrue\nnull\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
