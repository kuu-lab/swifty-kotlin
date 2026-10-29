#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func unsignedDefaultsAreExportedFromAdditionalFacades(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = "package anchor\nfun main() {}"
            let extensionSource = """
            @file:kotlin.jvm.JvmName("Values")
            package example.values
            fun UInt.bump(delta: UInt = 1u): UInt = this + delta
            fun signed(value: Int, delta: Int = 1): Int = value + delta
            """
            let result = try compile(source, root: root, mode: mode,
                                     additionalSources: [("values.kt", extensionSource)])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let runtime = try m11Runtime()
            let details = try javap(["-p", "-s", "-classpath", artifact, "example.values.Values"])
            try #require(details.exitCode == 0, Comment(rawValue: details.stderr))
            let method = try #require(details.stdout.split(separator: "\n").first {
                $0.contains(" bump-") && !$0.contains("$default")
            })
            let name = try #require(method.split(separator: "(").first?.split(separator: " ").last)
            #expect(details.stdout.contains(" \(name)$default("))
            #expect(details.stdout.contains(" signed$default("))

            try """
            import java.lang.reflect.Method;
            public class DefaultsConsumer {
                public static void main(String[] args) throws Exception {
                    Class<?> type = Class.forName("example.values.Values");
                    Method unsigned = null;
                    for (Method method : type.getDeclaredMethods()) {
                        if (method.getName().startsWith("bump-") && method.getName().endsWith("$default")) unsigned = method;
                    }
                    if (unsigned == null) throw new NoSuchMethodException("unsigned default");
                    System.out.println(unsigned.invoke(null, 41, 0, 1, null));
                    System.out.println(unsigned.invoke(null, 41, 8, 0, null));
                    Method signed = type.getDeclaredMethod("signed$default", int.class, int.class, int.class, Object.class);
                    System.out.println(signed.invoke(null, 10, 0, 2, null));
                }
            }
            """.write(to: root.appendingPathComponent("DefaultsConsumer.java"), atomically: true, encoding: .utf8)
            let compilation = try javac(["-cp", artifact + ":" + runtime, root.appendingPathComponent("DefaultsConsumer.java").path])
            try #require(compilation.exitCode == 0, Comment(rawValue: compilation.stderr))
            let execution = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "DefaultsConsumer"])
            #expect(execution.exitCode == 0, Comment(rawValue: execution.stderr))
            #expect(execution.stdout == "42\n49\n11\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
