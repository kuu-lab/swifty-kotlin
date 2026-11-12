#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func groupingByEachCountRunsAgainstOfficialRuntimeAndJavaConsumer() throws {
        let source = #"""
        fun repeatedKeyCounts(): Map<String, Int> =
            listOf("a", "b", "a").groupingBy { it }.eachCount()

        fun main() {
            println(repeatedKeyCounts())
            println(emptyList<String>().groupingBy { it }.eachCount())

            val calls = mutableListOf<String>()
            val grouping = listOf("b", "a", "b").groupingBy {
                calls.add("key:$it")
                it
            }
            println(calls.size)
            println(grouping.eachCount())
            println(calls.joinToString("|"))
        }
        """#
        let expected = "{a=2, b=1}\n{}\n0\n{b=2, a=1}\nkey:b|key:a|key:b\n"

        try withWorkspace { root in
            let compiled = try compile(source, root: root, mode: .jvmJar)
            let diagnostics = compiled.1.map(\.message).joined(separator: "\n")
            try #require(compiled.0 == 0, "\(diagnostics)")

            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent("hello.jar").path
            let generated = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(generated.stdout == expected)
            #expect(generated.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == generated.stdout)
            #expect(reference.stderr.isEmpty)

            let javaConsumer = #"""
            import java.util.Map;

            public final class JavaConsumer {
                public static void main(String[] args) {
                    Map<String, Integer> counts = HelloKt.repeatedKeyCounts();
                    if (!"{a=2, b=1}".equals(counts.toString())) {
                        throw new AssertionError(counts);
                    }
                    System.out.println(counts);
                }
            }
            """#
            try javaConsumer.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            let javaSource = root.appendingPathComponent("JavaConsumer.java").path
            let javaCompiled = try javac(["-cp", artifact + ":" + runtime, "-d", root.path, javaSource])
            try #require(javaCompiled.exitCode == 0, "\(javaCompiled.stderr)")
            let javaExecution = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "JavaConsumer"])
            #expect(javaExecution.stdout == "{a=2, b=1}\n")
            #expect(javaExecution.stderr.isEmpty)
        }
    }

    @Test
    func groupingByRejectsNonIterableReceiver() throws {
        try withWorkspace { root in
            let result = try compile("fun main() { (3).groupingBy { it } }", root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.message.contains("Unresolved member function 'groupingBy'") })
        }
    }
}
#endif
