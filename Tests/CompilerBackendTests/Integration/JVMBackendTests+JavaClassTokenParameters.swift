#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaClassParameterAcceptsKotlinClassLiteral() throws {
        try withWorkspace { root in
            let javaSource = """
                package dep;
                public class Registry {
                    public static String label(Class<?> type) { return type.getSimpleName(); }
                }
                """
            try javaSource.write(to: root.appendingPathComponent("Registry.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "Registry.java"], root: root)
            let source = """
                import dep.Registry

                class Entry
                fun main() {
                    println(Registry.label(Entry::class.java))
                    println(Registry.label(Int::class.java))
                    val entry: Any = Entry()
                    println(Registry.label(entry::class.java))
                }
                """
            let dependencies = root.appendingPathComponent("deps").path
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmClass, classpath: [dependencies])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let classes = root.appendingPathComponent("classes").path
            let result = try java(["-cp", "\(classes):\(dependencies)", "HelloKt"])
            #expect(result.stdout == "Entry\nint\nEntry\n")
        }
    }
}
#endif
