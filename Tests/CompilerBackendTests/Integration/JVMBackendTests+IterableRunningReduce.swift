#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func iterableRunningReduceMatchesKotlincForJavaConsumer() throws {
        try withWorkspace { root in
            let runtime = try m11Runtime()
            let runtimeEntries = runtime.components(separatedBy: ":")
            let source = #"""
            package demo

            fun runningReduceValues(): List<Int> {
                val values: Iterable<Int> = listOf(1, 2, 3)
                return values.runningReduce { accumulator, element -> accumulator + element }
            }

            fun runningReduceEmpty(): List<Int> {
                val values: Iterable<Int> = emptyList()
                return values.runningReduce { accumulator, element -> accumulator + element }
            }

            fun runningReduceSingleton(): List<Int> {
                val values: Iterable<Int> = listOf(42)
                return values.runningReduce { accumulator, element -> accumulator + element }
            }

            fun runningReduceOrder(): List<Int> {
                val calls = mutableListOf<String>()
                val values: Iterable<Int> = listOf(1, 2, 3)
                val result = values.runningReduce { accumulator, element ->
                    calls.add("$accumulator:$element")
                    accumulator + element
                }
                println(calls)
                return result
            }

            fun main() {
                println(listOf(1, 2, 3).runningReduce { a, b -> a + b })
            }
            """#
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: runtimeEntries)
            let diagnostics = compiled.1.map(\.message)
            try #require(compiled.0 == 0, "\(diagnostics)")
            let artifact = root.appendingPathComponent("hello.jar").path

            let consumer = #"""
            public class JavaConsumer {
                public static void main(String[] args) {
                    demo.HelloKt.main();
                    System.out.println(demo.HelloKt.runningReduceEmpty());
                    System.out.println(demo.HelloKt.runningReduceSingleton());
                    System.out.println(demo.HelloKt.runningReduceOrder());
                }
            }
            """#
            try consumer.write(to: root.appendingPathComponent("JavaConsumer.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-cp", artifact + ":" + runtime, "JavaConsumer.java"], root: root)
            let classpath = root.path + ":" + artifact + ":" + runtime
            let candidate = try java(["-cp", classpath, "JavaConsumer"])

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.path + ":" + root.appendingPathComponent("reference.jar").path + ":" + runtime, "JavaConsumer"])
            let expected = "[1, 3, 6]\n[]\n[42]\n[1:2, 3:3]\n[1, 3, 6]\n"
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }

    @Test
    func iterableRunningReduceRejectsNonIterableReceiver() throws {
        try withWorkspace { root in
            let source = "fun main() { (42).runningReduce { left, right -> left + right } }"
            let rejected = try compile(source, root: root, mode: .jvmJar)
            #expect(rejected.0 != 0)
            #expect(rejected.1.contains { $0.message.contains("runningReduce") }, "\(rejected.1.map(\.message))")
            #expect(!rejected.1.contains { $0.message.contains("Unsupported JVM collection member: runningReduce") })
        }
    }
}
#endif
